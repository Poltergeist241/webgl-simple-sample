#version 300 es
precision highp float;
out vec4 fragColor;
uniform vec2 iResolution;
uniform float iTime;

uniform sampler2D iTexture0;
uniform sampler2D iTexture1;
uniform sampler2D iTexture2;

#define MATERIAL_CONST 0
#define MATERIAL_BOX 1
#define MATERIAL_FLOOR 2

const float pi = 3.141593;

const int MAX_MARCHING_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;
const float PRECISION = 0.001;

// Rotation matrix around the X axis.
// Winkel in Einheit Radians, d.h. theta = pi entspricht 180°
mat3 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(1, 0, 0),
        vec3(0, c, -s),
        vec3(0, s, c)
    );
}

// Rotation matrix around the Y axis.
mat3 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, 0, s),
        vec3(0, 1, 0),
        vec3(-s, 0, c)
    );
}

// Rotation matrix around the Z axis.
mat3 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, -s, 0),
        vec3(s, c, 0),
        vec3(0, 0, 1)
    );
}


mat3 diagonalMatrix(float x, float y, float z) {
    return mat3(
        vec3(x, 0, 0),
        vec3(0, y, 0),
        vec3(0, 0, z)
    );
}

mat3 identity() {
    return diagonalMatrix(1., 1., 1.);
}

struct Surface {
    float sd; // Abstand des Rays vom Objekt
    vec3 col; // <-- die Objekte dürfen eine intrinsische Farbe haben
    int material; // wir verlagern die Zuweisung der Farben auf nach dem Ray Marching...
    vec2 uv; // wir müssen aber mitführen
};

void wobbleDistort(inout Surface surface, vec3 p, float amp, vec3 scale) {
    surface.sd += amp * sin(scale.x*p.x) * sin(scale.y*p.y) * sin(scale.z*p.z);
}

float checkerboard(vec2 p, float scale) {
    vec2 ip = floor(p * scale);
    return mod(ip.x + ip.y, 2.0);
}

float surfaceCheckerPattern(vec3 p, float checkerSize) {
    vec2 surface = vec2(
        atan(p.z, p.x) / (2. * 3.14159) + 0.5,
        p.y / 2. + 0.5
    );
    return checkerboard(surface, checkerSize);
}

Surface sdPatternSphere( vec3 p, vec3 b, vec3 offset, vec3 col, mat3 transform, vec3 checkerCol, float nSegments) {
    p = (p - offset) * transform;
    vec3 q = abs(p) - b;
    float d = length(p / b) - 1.;
    col = mix(col, checkerCol, surfaceCheckerPattern(p, nSegments));
    return Surface(d, col, 0, vec2(0.));
}

Surface sdSphere( vec3 p, vec3 b, vec3 offset, vec3 col, mat3 transform) {
    p = (p - offset) * transform;
    vec3 q = abs(p) - b;
    float d = length(p / b) - 1.;
    return Surface(d, col, 0, vec2(0));
}

Surface sdBox( vec3 p, vec3 b, vec3 offset, vec3 col, mat3 transform) {
    p = (p - offset) * transform;
    vec3 q = abs(p) - b;
    float d = length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
    return Surface(d, col, 0, vec2(0));
}

Surface sdTexturedBox( vec3 p, vec3 b, vec3 offset, vec3 col, mat3 transform) {
    p = (p - offset) * transform;
    vec3 q = abs(p) - b;
    float d = length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);

    // Koordinatentransformation:
    // Um Textur zuzuordnen, müssen wir uns in den Würfel hineinversetzen.
    // - In seinem eigenen Koordinatensystem rotiert er nicht,
    // - die Mitte ist nicht bei p (Weltkoordinaten), sondern bei vec3(0)
    // - und auch die Skalierung (b) für seine prinzipielle Würfelhaftigkeit egal.
    vec3 a = 0.5 * p / b;
    // damit geht der Würfel in jeder Dimension von einer Wand bei -0.5 zu einer bei +0.5

    // Gradient um oben/unten auseinander halten zu können.
    col = vec3(
        0.5 + a.z,
        0.5 + a.x,
        0.5 - a.z // aber zu Farbmischungen kommen wir noch.
    );

    vec2 uv;
    // Um Zuordnung zu verstehen:
    // mal auskommentieren oder sign()-Abhängigkeit entfernen,
    // oder mit uv = vec2(0); die Textur auf der Seite deaktiveren.
    if (abs(a.z) > 0.5) {
        uv = vec2(0.5 + a.x * sign(a.z), 0.5 - a.y);
    } else if (abs(a.y) > 0.5) {
        uv = vec2(0.5 + a.x, 0.5 + a.z * sign(a.y));
    } else if (abs(a.x) > 0.5) {
        uv = vec2(0.5 - a.z * sign(a.x), 0.5 - a.y);
    }
    // Reminder: if() generell überdenken, aber das reicht auch,
    // wenn irgendwo konkret ein Performanceproblem vorliegt.

    // oder wäre das hier viel lehrreicher?
//    uv = mix(
//        mix(
//            vec2(0.5 + a.x * sign(a.z), 0.5 - a.y),
//            vec2(0.5 + a.x * sign(a.y), 0.5 + a.z),
//            step(0.5, abs(a.y))
//        ),
//        vec2(0.5 - a.z * sign(a.x), 0.5 - a.y),
//        step(0.5, abs(a.x))
//    );

    return Surface(d, col, MATERIAL_BOX, uv);
}

// Hash function for noise generation
float hash(vec2 n) {
    return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float hash14(vec4 p)
{
    uvec4 q = uvec4(ivec4(p)) * uvec4(1597334673U, 3812015801U, 2798796415U, 1979697957U);
    uint n = (q.x ^ q.y ^ q.z ^ q.w) * 1597334673U;
    return float(n) * 2.328306437080797e-10;
}

float hash14(vec2 p)
{
    // funny enough, with 0. the glitches stay.
    return hash14(vec4(p, 1., 1.));
}

// um schnell zwischen Hashfunktionen zu wechseln
#define HASH hash14

// "Value Noise" function
float noise(vec2 p){
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    fp = fp * fp * (3.0 - 2.0 * fp); // this equals smoothstep (in the interval [0,1])
    // fp = fp * fp * fp * (fp * (fp * 6. - 15.) + 10.); // "smootherstep"

    return mix(
        mix(
            HASH(ip),
            HASH(ip+vec2(1.0,0.0)),
            fp.x
        ),
        mix(
            HASH(ip+vec2(0.0,1.0)),
            HASH(ip+vec2(1.0,1.0)),
            fp.x
        ),
        fp.y
    );
}

// Fractional Brownian Motion for low-frequency noise
#define FBM_ITERATIONS 10
float fbm(vec2 p) {
    float f = 0.0;
    float amp = 0.5;
    for (int i = 0; i < FBM_ITERATIONS; i++) {
        f += amp * noise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return f;
}

float floorLevel = -1.;
float noiseHeight = 3.; // was passiert bei zu hohen Werten, v.A. in Verbindung mit hohen FBM_ITERATIONS?
float noiseFreq = 0.2;

Surface sdFloor(vec3 p) {
    vec3 floorColor = vec3(1.);
    // bisher: wurde hier definiert -> man verfolge MATERIAL_FLOOR
    // floorColor = (0.5 + 0.15 * mod(floor(p.x) + floor(p.z), 4.0)) * vec3(0.9, 1., .95);
    vec2 floorUv = fract(p.xz); // fract() for texture wrapping, could scale like fract(0.25 * p.xz)
    float d = p.y - floorLevel;
    // flaches Terrain: exit here.
    // return Surface(d, floorColor, MATERIAL_FLOOR, floorUv);

    // wir machen es uns hier leicht -- was ist mit den Normalenvektoren?
    // -> mal diffuse lighting einschalten
    float someOffset = 5.3; // hashes sehen um 0 oft auffällig auf
    float noise = fbm(noiseFreq * p.xz + someOffset);
    float noisyLevel = floorLevel - noiseHeight * (noise - 0.5);
    d = p.y - noisyLevel;
    return Surface(d, floorColor, MATERIAL_FLOOR, floorUv);
}

Surface takeCloser(Surface obj1, Surface obj2) {
    if (obj2.sd < obj1.sd) {
        return obj2;
    }
    return obj1;
}

vec3 firstCubePos = vec3(1.5, 0.5, -1.);

Surface sdScene(vec3 p) {
    Surface obj;
    Surface co = sdFloor(p);

    obj = sdTexturedBox(p, vec3(0.6), firstCubePos, vec3(0.3, 0.65, 0.9), rotateX(-0.2 * pi + iTime));
    co = takeCloser(co, obj);

    obj = sdTexturedBox(p, vec3(0.6), firstCubePos + vec3(-3.0, 0., 0.), vec3(0.3, 0.65, 0.9), rotateY(+0.3 * pi + iTime));
    co = takeCloser(co, obj);

    /*
    obj = sdPatternSphere(p, vec3(1.), vec3(-2., floorLevel + 1., -2.), vec3(1, 0.1, 0.8), identity(), vec3(0.5, 0.2, 0.8), 8.);

    mat3 ballTransform = rotateY(0.5 * iTime);
    obj = sdSphere(p, vec3(1.), vec3(-2., floorLevel + 1., -2.), vec3(1, 0.6, 0.8), ballTransform);
    co = takeCloser(co, obj);
    */
    return co;
}

void applyMaterial(inout Surface s, vec3 ray) {
    if (s.material == MATERIAL_BOX) {
        s.col *= texture(iTexture0, s.uv).rgb;
        // Bock auf Holz?
        float scale = 4.;
        vec3 holz = texture(iTexture2, s.uv / scale).rgb;
        // naive Farbmischung: mal mit Grundrechenarten rumprobieren.
        // s.col = holz;
        // s.col *= holz;
        // s.col = min(s.col, holz);
        // s.col = max(s.col, holz);
        // s.col = pow(s.col + holz, vec3(1.4));  // <-- etc... you know the drill
        // s.col = mix(s.col, holz, 0.5);
        // s.col = mix(s.col, holz, 0.5 - 0.5 * cos(iTime));
//         s.col = 1. - (1. - s.col) * (1. - holz); // "Screen"
        // "Overlay":
//        s.col = length(s.col) < 0.5
//            ? 2. * s.col * holz
//            : 1. - 2. * (1. - s.col) * (1. - holz);
//         s.col = s.col - holz + 2. * s.col * holz; // "Soft Light"
//         s.col = holz - s.col + 2. * s.col * holz; // "Soft Light", invers
    }
    else if (s.material == MATERIAL_FLOOR) {
        s.col *= (0.5 + 0.15 * mod(floor(ray.x) + floor(ray.z), 4.0)) * vec3(0.9, 1., .95);
    }
    s.col = clamp(s.col, vec3(0.), vec3(1.));
}

Surface rayMarch(vec3 ro, vec3 rd, float start, float end) {
    float rayLength = start; // rayLength is usually just called t
    Surface co;

    for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
        co = sdScene(ro + rayLength * rd);
        rayLength += co.sd;

        if (co.sd < PRECISION || rayLength > end) {
            break;
        }
    }

    co.sd = rayLength;
    return co;
}

float rayMarchShadow( in vec3 ro, in vec3 rd)
{
    float tMin = 0.05;
    float tMax = 3.;
    float w = 0.002;

    float d = 1.0;
    float t = tMin;

    for (int i=0; i < MAX_MARCHING_STEPS; i++)
    {
        float h = sdScene( ro + rd*t ).sd;
        d = min( d, h/(w*t) );
        t += h;

        if (d < PRECISION || t > tMax ) {
            break;
        }
    }

    //return res;

    d = clamp( d, 0.0, 1.0 );
    //return res;

    d = smoothstep(0., 1., d);
    return d;
}

vec3 calcNormal(in vec3 p) {
    vec2 epsilon = vec2(1.0, -1.0) * 0.0005;
    return normalize(
        epsilon.xyy * sdScene(p + epsilon.xyy).sd +
        epsilon.yyx * sdScene(p + epsilon.yyx).sd +
        epsilon.yxy * sdScene(p + epsilon.yxy).sd +
        epsilon.xxx * sdScene(p + epsilon.xxx).sd
    );
}

float PHI = 1.61803398874989484820459;  // Golden Ratio

float gold_noise(in vec2 xy, in float seed) {
    return fract(tan(distance(xy * PHI, xy) * seed) * xy.x);
}

void main() {
    vec2 uv = (2.0 * gl_FragCoord.xy - iResolution.xy) / iResolution.y;

    // transform uv but only for background
    vec2 bgUv = uv + 0.0 * vec2(0.1 * iTime, 0.);
    float bgRotationSpeed = 0.0; // 0.1;
    float bgScale = 1.; // z.B. mal 0.6 - wie üblich: invers denken
    bgUv = bgScale * (rotateZ(bgRotationSpeed * iTime) * vec3(bgUv, 1.)).xy;
    vec2 st = fract(bgUv);
    vec4 bgColor = texture(iTexture1, st);

    // Beispiel Textur-Processing: Radial Motion Blur
    // man achte aber auf die Ecken -> Granularität sichtbar
//    bgColor.xyz = vec3(0);
//    float blurSteps = 32.;
//    float blurLength = 5.;
//    float phi = 0.03 * iTime;
//    for (float step=0.; step < blurSteps; step += 1.) {
//        phi -= 0.005;
//        bgUv = (rotateZ(phi) * vec3(uv, 1.)).xy;
//        st = fract(bgUv);
//        vec3 texColor = texture(iTexture1, st).xyz * exp(-step / blurLength);
//        bgColor.xyz = max(texColor, bgColor.xyz);
//    }

    // anderes Beispiel: Radial Blur
//    bgColor.xyz = vec3(0);
//    float blurSteps = 32.;
//    float blurLength = 15.;
//    float factor = 0.005;
//    vec2 center = vec2(0., 0.6 + 0.2 * sin(iTime));
//    for (float step=0.; step < blurSteps; step += 1.) {
//        bgScale = 1. + factor * step;
//        bgUv = bgScale * (uv - center) + center;
//        st = fract(bgUv);
//        vec3 texColor = texture(iTexture1, st).xyz * exp(-step / blurLength);
//        bgColor.xyz = max(texColor, bgColor.xyz);
//    }

    vec4 col = vec4(0.);
    float d;

    vec3 ro = vec3(0., 2., 1.);
    float fov = 45. * pi / 180.; // 45° ist natürlicher, bleibt aber eine Designentscheidung
    vec3 rd = normalize(vec3(uv, -fov));
    rd *= rotateX(-0.2 * pi);
    // rd *= rotateY(0.02 * sin(3. * iTime));

    Surface co = rayMarch(ro, rd, MIN_DIST, MAX_DIST);

    if (co.sd < MAX_DIST) {
        vec3 p = ro + rd * co.sd;
        applyMaterial(co, p);
        vec3 normal = calcNormal(p);
        vec3 lightPosition = firstCubePos + vec3(0., 3., 3.);
        lightPosition.x += 5. * cos(iTime);
        lightPosition.z += 3. * sin(iTime);
        vec3 lightDirection = normalize(lightPosition - p);

        // lightDirection = normalize(vec3(2. * cos(iTime), 0.5, 0.));
        // lightDirection = normalize(vec3(0., 1., 0.));

        // Erinnerung: _irgendwie_ muss Abstand "d" zu einer Farbe werden.
        // wie, sind quasi nur noch die Details :)
        // d = co.sd;
        d = clamp(co.sd, 0., 1.);

        // could also have parallel light
        // lightDirection = normalize(vec3(0., 1., 0.));

        // Lambertian reflection:
        // proportional to amount of light hitting the surface
        // i.e. dot(normal, lightDir) ~ large if Angle between normal and light is low
        // Quasi "perfekte" Diffusion, warum?
        float diffuse = dot(normal, lightDirection);
        diffuse = clamp(diffuse, 0., 1.);
        d = mix(d, diffuse, 1.);

        // sekundäres Ray Marching für Schatten
        float shadow = rayMarchShadow(p, lightDirection);
        d = mix(d, shadow, 0.8);

        // Specular reflection:
        // proportional to angle between ray and reflections
        vec3 refl = reflect(lightDirection, normal);
        float specular = dot(refl, normalize(p));
        specular = clamp(specular, 0., 1.);
        specular = pow(specular, 3.);
        // Idee: unterschiedliche Materialien spiegeln unterschiedlich stark.
        specular = co.material == MATERIAL_FLOOR ? 0.1 : 1.;

        d = mix(d, specular, 0.5);


        // verschiedenartiges Color Grading
        // col.xyz = pow(co.sd, 0.1) * co.col;

        col.xyz = pow(d, 0.3) * co.col;

        //        dif = mix(dif, co.sd, 0.03);
        //        dif = mix(dif, dif * co.sd, 0.24);
        //        float clamped_dif = clamp(dif, 0., 1.);
        //        float graded_dif = atan(dif);
        //        dif = mix(clamped_dif, graded_dif, 1.);
        //        dif = pow(dif, 2.);

        // aufhellen, je mehr Blick Richtung Licht
        //col.xyz = mix(col.xyz, vec3(1), pow(clamp(dot(p, lightDirection), 0., 1.), 100.));
        // float richtungInsLicht = clamp(dot(rd, lightPosition - ro), 0., 1.);
        // col.xyz *= exp(-1. * (1. - richtungInsLicht));

        // Distance Fog: Abschwächen je nach durchlaufenem Abstand
        float fog = exp(-0.00001 * pow(co.sd, 4.));
        col.xyz *= fog;
        col.a = step(0.1, fog);
        // col.a = exp(-0.0001 * pow(co.sd, 3.));
        // col.a = 1. - clamp(pow(length(col.xyz), 50.), 0., 1.);
    }

    // Beispiel Post-Processing (transformiert nur noch Farbe -> Farbe, nicht mehr Geometrie)
    // col = atan(8. * pow(col, vec3(5.)));

//    float rnd;
//    rnd = fract(1000000. * sin(321231. * uv.x + 34928. * uv.y)); // see it flickering?
//    rnd = hash14(floor(0.1 * gl_FragCoord));
//    col.xyz = vec3(rnd);

    //uv = floor(2. * uv);


//    rnd = fract(
//        sin(
//            dot(uv.xy, vec2(12.9898,78.233))
//        ) * 43758.5453123
//    );

    // exkursion ins pseudochaos
//    col.xyz = vec3(1.);
//    col.xyz *= rnd;
//    col.a = 1.;

    // col.xyz = vec3(gold_noise(uv, iTime));


    fragColor = mix(bgColor, vec4(col.xyz, 1.), col.a);
    //fragColor = mix(backgroundColor, col, col.a);
    
    // quick check: so sähe das direkt gemappt aus.
    // Man achte auf die Werte der Koordinaten und die Texturparameter.
    // (v.A. bei einer Textur, die keinen schwarzen Rand hat.)
//    fragColor = texture(iTexture2, uv);

    // Post Processing - Vignette
    vec3 post = fragColor.xyz;

    //    post *= exp( -0.03 * pow(length(uv), 5.7));
//    post = clamp(post, 0.0, 1.0);
//    post = pow(post, vec3(0.7));
//    post = post * 0.4 + 0.6 * smoothstep(vec3(0), vec3(1), post) + vec3(0.0,0.0,0.04);
//
    // Einfacher RGB-basierter Filter wäre z.B. so einer. Aber damit geht nicht viel.
    // post.r = max(post.g, post.b);

    // --> verschoben auf postProcessing.glsl, wird in 8_Multipass.js als 2nd Pass genutzt.

    fragColor.xyz = post;
}
