// Raytracing in one weekend, chapter 12: Where next? Created by Reinder Nijhoff 2018
// @reindernijhoff
//
// https://www.shadertoy.com/view/XlycWh
//
// These shaders are my implementation of the raytracer described in the (excellent)
// book "Raytracing in one weekend" [1] by Peter Shirley (@Peter_shirley). I have tried
// to follow the code from his book as much as possible.
//
// [1] http://in1weekend.blogspot.com/2016/01/ray-tracing-in-one-weekend.html
//
// Raytracing in one weekend, chapter 12: Where next? Created by Reinder Nijhoff 2018
// Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
// @reindernijhoff
//
// https://www.shadertoy.com/view/XlycWh
//
// These shaders are my implementation of the raytracer described in the (excellent)
// book "Raytracing in one weekend" [1] by Peter Shirley (@Peter_shirley). I have tried
// to follow the code from his book as much as possible, but I had to make some changes
// to get it running in a fragment shader:
//
// - There are no classes (and methods) in glsl so I use structs and functions instead.
//   Inheritance is implemented by adding a type variable to the struct and adding ugly
//   if/else statements to the (not so overloaded) functions.
// - The scene description is procedurally implemented in the world_hit function to save
//   memory.
// - The color function is implemented using a loop because it is not possible to have a
//   recursive function call in glsl.
// - Only one sample per pixel per frame is calculated. Samples of all frames are added
//   in Buffer A and averaged in the Image tab.
//
// You can find the raytracer / pathtracer in Buffer A.
//
// = Ray tracing in one week =
// Chapter  7: Diffuse                           https://www.shadertoy.com/view/llVcDz
// Chapter  9: Dielectrics                       https://www.shadertoy.com/view/MlVcDz
// Chapter 11: Defocus blur                      https://www.shadertoy.com/view/XlGcWh
// Chapter 12: Where next?                       https://www.shadertoy.com/view/XlycWh
//
// = Ray tracing: the next week =
// Chapter  6: Rectangles and lights             https://www.shadertoy.com/view/4tGcWD
// Chapter  7: Instances                         https://www.shadertoy.com/view/XlGcWD
// Chapter  8: Volumes                           https://www.shadertoy.com/view/XtyyDD
// Chapter  9: A Scene Testing All New Features  https://www.shadertoy.com/view/MtycDD
//
// This particular shader can be optimized (a lot) by using an acceleration structure,
// as done in my shader "More spheres": https://www.shadertoy.com/view/lsX3DH
//
// [1] http://in1weekend.blogspot.com/2016/01/ray-tracing-in-one-weekend.html
//


#version 300 es
precision highp float;
out vec4 frag_color;

uniform vec2 iResolution;
uniform float iTime;
uniform int iFrame;
uniform int iPassIndex;
uniform sampler2D iChannel0;

#define MAX_FLOAT 1e5
#define MAX_RECURSION (6+min(0,iFrame))

#define LAMBERTIAN 0
#define METAL 1
#define DIELECTRIC 2

//
// Hash functions by Nimitz:
// https://www.shadertoy.com/view/Xt3cDn
//

uint base_hash(uvec2 p) {
    p = 1103515245U*((p >> 1U)^(p.yx));
    uint h32 = 1103515245U*((p.x)^(p.y>>3U));
    return h32^(h32 >> 16);
}

float g_seed = 0.;

float hash1(inout float seed) {
    uint n = base_hash(floatBitsToUint(vec2(seed+=.1,seed+=.1)));
    return float(n)/float(0xffffffffU);
}

vec2 hash2(inout float seed) {
    uint n = base_hash(floatBitsToUint(vec2(seed+=.1,seed+=.1)));
    uvec2 rz = uvec2(n, n*48271U);
    return vec2(rz.xy & uvec2(0x7fffffffU))/float(0x7fffffff);
}

vec3 hash3(inout float seed) {
    uint n = base_hash(floatBitsToUint(vec2(seed+=.1,seed+=.1)));
    uvec3 rz = uvec3(n, n*16807U, n*48271U);
    return vec3(rz & uvec3(0x7fffffffU))/float(0x7fffffff);
}

//
// Ray trace helper functions
//

float schlick(float cosine, float ior) {
    float r0 = (1.-ior)/(1.+ior);
    r0 = r0*r0;
    return r0 + (1.-r0)*pow((1.-cosine),5.);
}

bool modified_refract(const in vec3 v, const in vec3 n, const in float ni_over_nt,
out vec3 refracted) {
    float dt = dot(v, n);
    float discriminant = 1. - ni_over_nt*ni_over_nt*(1.-dt*dt);
    if (discriminant > 0.) {
        refracted = ni_over_nt*(v - n*dt) - n*sqrt(discriminant);
        return true;
    } else {
        return false;
    }
}

vec2 random_in_unit_disk(inout float seed) {
    vec2 h = hash2(seed) * vec2(1.,6.28318530718);
    float phi = h.y;
    float r = sqrt(h.x);
    return r * vec2(sin(phi),cos(phi));
}

vec3 random_in_unit_sphere(inout float seed) {
    vec3 h = hash3(seed) * vec3(2.,6.28318530718,1.)-vec3(1,0,0);
    float phi = h.y;
    float r = pow(h.z, 1./3.);
    return r * vec3(sqrt(1.-h.x*h.x)*vec2(sin(phi),cos(phi)),h.x);
}

//
// Ray
//

struct ray {
    vec3 origin, direction;
};

//
// Material
//

struct material {
    int type;
    vec3 albedo;
    float v;
};

//
// Hit record
//

struct hit_record {
    float t;
    vec3 p, normal;
    material mat;
};

bool material_scatter(const in ray r_in, const in hit_record rec, out vec3 attenuation,
out ray scattered) {
    if(rec.mat.type == LAMBERTIAN) {
        vec3 rd = normalize(rec.normal + random_in_unit_sphere(g_seed));
        scattered = ray(rec.p, rd);
        attenuation = rec.mat.albedo;
        return true;
    } else if(rec.mat.type == METAL) {
        vec3 rd = reflect(r_in.direction, rec.normal);
        scattered = ray(rec.p, normalize(rd + rec.mat.v*random_in_unit_sphere(g_seed)));
        attenuation = rec.mat.albedo;
        return true;
    } else if(rec.mat.type == DIELECTRIC) {
        vec3 outward_normal, refracted,
        reflected = reflect(r_in.direction, rec.normal);
        float ni_over_nt, reflect_prob, cosine;

        attenuation = vec3(1);
        if (dot(r_in.direction, rec.normal) > 0.) {
            outward_normal = -rec.normal;
            ni_over_nt = rec.mat.v;
            cosine = dot(r_in.direction, rec.normal);
            cosine = sqrt(1. - rec.mat.v*rec.mat.v*(1.-cosine*cosine));
        } else {
            outward_normal = rec.normal;
            ni_over_nt = 1. / rec.mat.v;
            cosine = -dot(r_in.direction, rec.normal);
        }

        if (modified_refract(r_in.direction, outward_normal, ni_over_nt, refracted)) {
            reflect_prob = schlick(cosine, rec.mat.v);
        } else {
            reflect_prob = 1.;
        }

        if (hash1(g_seed) < reflect_prob) {
            scattered = ray(rec.p, reflected);
        } else {
            scattered = ray(rec.p, refracted);
        }
        return true;
    }
    return false;
}

//
// Hitable, for now this is always a sphere
//

struct hitable {
    vec3 center;
    float radius;
};

bool hitable_hit(const in hitable hb, const in ray r, const in float t_min,
const in float t_max, inout hit_record rec) {
    // always a sphere
    vec3 oc = r.origin - hb.center;
    float b = dot(oc, r.direction);
    float c = dot(oc, oc) - hb.radius * hb.radius;
    float discriminant = b * b - c;
    if (discriminant < 0.0) return false;

    float s = sqrt(discriminant);
    float t1 = -b - s;
    float t2 = -b + s;

    float t = t1 < t_min ? t2 : t1;
    if (t < t_max && t > t_min) {
        rec.t = t;
        rec.p = r.origin + t*r.direction;
        rec.normal = (rec.p - hb.center) / hb.radius;
        return true;
    } else {
        return false;
    }
}

//
// Camera
//

struct camera {
    vec3 origin, lower_left_corner, horizontal, vertical, u, v, w;
    float lens_radius;
};

camera camera_const(const in vec3 lookfrom, const in vec3 lookat, const in vec3 vup,
const in float vfov, const in float aspect, const in float aperture,
const in float focus_dist) {
    camera cam;
    cam.lens_radius = aperture / 2.;
    float theta = vfov*3.14159265359/180.;
    float half_height = tan(theta/2.);
    float half_width = aspect * half_height;
    cam.origin = lookfrom;
    cam.w = normalize(lookfrom - lookat);
    cam.u = normalize(cross(vup, cam.w));
    cam.v = cross(cam.w, cam.u);
    cam.lower_left_corner = cam.origin  - half_width*focus_dist*cam.u -half_height*focus_dist*cam.v - focus_dist*cam.w;
    cam.horizontal = 2.*half_width*focus_dist*cam.u;
    cam.vertical = 2.*half_height*focus_dist*cam.v;
    return cam;
}

ray camera_get_ray(camera c, vec2 uv) {
    vec2 rd = c.lens_radius*random_in_unit_disk(g_seed);
    vec3 offset = c.u * rd.x + c.v * rd.y;
    return ray(c.origin + offset,
    normalize(c.lower_left_corner + uv.x*c.horizontal + uv.y*c.vertical - c.origin - offset));
}

//
// Color & Scene
//

bool world_hit(const in ray r, const in float t_min,
const in float t_max, out hit_record rec) {
    rec.t = t_max;
    bool hit = false;

    if (hitable_hit(hitable(vec3(0,-1000,-1),1000.),r,t_min,rec.t,rec)) hit=true,rec.mat=material(LAMBERTIAN,vec3(.5),0.);

    if (hitable_hit(hitable(vec3( 2,1,2),1.),r,t_min,rec.t,rec))        hit=true,rec.mat=material(DIELECTRIC,vec3(0),1.5);
    if (hitable_hit(hitable(vec3(-4,1,0),1.),r,t_min,rec.t,rec))        hit=true,rec.mat=material(LAMBERTIAN,vec3(.4,.2,.1),0.);
    if (hitable_hit(hitable(vec3( 4.,1.,-0.5),1.),r,t_min,rec.t,rec))   hit=true,rec.mat=material(METAL     ,vec3(.7,.6,.5),0.);

    int NO_UNROLL = min(0,iFrame);
    for (int a = -11; a < 11+NO_UNROLL; a++) {
        for (int b = -11; b < 11+NO_UNROLL; b++) {
            float m_seed = float(a) + float(b)/1000.;
            vec3 rand1 = hash3(m_seed);
            vec3 center = vec3(float(a)+.9*rand1.x,.2,float(b)+.9*rand1.y);
            float choose_mat = rand1.z;

            if (distance(center,vec3(4,.2,0)) > .9) {
                if (choose_mat < .8) { // diffuse
                    if (hitable_hit(hitable(center,.2),r,t_min,rec.t,rec)) {
                        hit=true, rec.mat=material(LAMBERTIAN, hash3(m_seed)* hash3(m_seed),0.);
                    }
                } else if (choose_mat < 0.95) { // metal
                    if (hitable_hit(hitable(center,.2),r,t_min,rec.t,rec)) {
                        hit=true, rec.mat=material(METAL,.5*(hash3(m_seed)+1.),.5*hash1(m_seed));
                    }
                } else { // glass
                    if (hitable_hit(hitable(center,.2),r,t_min,rec.t,rec)) {
                        hit=true, rec.mat=material(DIELECTRIC,vec3(0),1.5);
                    }
                }
            }
        }
    }

    return hit;
}

vec3 color(in ray r) {
    vec3 col = vec3(1);
    hit_record rec;

    for (int i=0; i<MAX_RECURSION; i++) {
        if (world_hit(r, 0.001, MAX_FLOAT, rec)) {
            ray scattered;
            vec3 attenuation;
            // Demo: mal durchprobieren (siehe Definitionen oben)
            // rec.mat.type = LAMBERTIAN;
            // rec.mat.type = METAL;
            // rec.mat.type = DIELECTRIC;
            if (material_scatter(r, rec, attenuation, scattered)) {
                col *= attenuation;
                r = scattered;
            } else {
                return vec3(0);
            }
        } else {
            float t = .5*r.direction.y + .5;
            col *= mix(vec3(1),vec3(.5,.7,1), t);
            return col;
        }
    }
    return vec3(0);
}

//
// Main
//

void main() {
    float frame = float(iFrame + 1);
    float frameScale = 1./float(iFrame + 1);

    vec2 st = gl_FragCoord.xy / iResolution.xy;
    vec4 image = texture(iChannel0, st);
    // manchmal sieht da so aus - hat genau denselben Zweck, Hauptunterschied sind: Integerkoordinaten statt normiert.
    // vec4 image = texelFetch(iChannel0, ivec2(gl_FragCoord.xy), 0);


    g_seed = float(base_hash(floatBitsToUint(gl_FragCoord.xy)))/float(0xffffffffU)+iTime;
    // Demo: Abschalten der stochastischen Variation:
    // g_seed = 0.;

    vec2 uv = (gl_FragCoord.xy + hash2(g_seed))/iResolution.xy;
    float aspect = iResolution.x/iResolution.y;
    vec3 lookfrom = vec3(13,2,3);
    vec3 lookat = vec3(0);

    camera cam = camera_const(lookfrom, lookat, vec3(0,1,0), 20., aspect, .1, 10.);
    ray r = camera_get_ray(cam, uv);
    vec3 col = color(r);

    if (iPassIndex == 1) {
        // ähnlich wie im Framebuffer-Ping-Pong-Shader,
        // aber braucht noch Bearbeitung:
        // 1) bisher ist im Alphakanal gemessen, wie viele Rays den Pixel getroffen haben
        //    --> es wird dadurch geteilt, damit die Farbe dem Mittelwert entspricht.
        //    --> OBACHT: Damit das geht, muss die Textur im richtigen Format aufgesetzt sein. Das ist tricky!
        // 2) (nur für hübsch) Simples Color Grading. ( Quadratwurzel sqrt(...) == pow(..., 0.5) )

        frag_color = vec4(sqrt(image.rgb / image.a), 1.);
        return;
    }

    frag_color = vec4(col, 1);

    if (iFrame > 0) {

        frag_color += image;

        // s. Anmerkung oben -- im RenderPass 0 erlauben wir uns, einfach alle Strahlentreffer aufzusummieren.
        // wenn wir im Hintergrund eine gewöhnliche "Fixed Point" Textur aufgesetzt haben, wird auf [0..1] geclampt.
        // In solche Fehler kann man Stunden stecken...
    }
}
