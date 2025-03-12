import {compile, createStaticVertexBuffer, initVertices} from "../webgl/setup.js";

/**
 * Hint about usage: every showcase file must have a default export like this
 */

import vertexShaderSource from "../shaders/basic.vertex.glsl";
import fragmentShaderSource from "../shaders/singleColor.glsl";


export default {
    title: "Very simple example",
    init: (gl) => {
        // QUESTION: what the... is this?
        createStaticVertexBuffer(
            gl,
            [
            0, 0.5, // Top
            -0.2, -0.5, // Bottom left
            0.2, -0.5, // Bottom right

            -0.45, 0, // Far left
            0.45, 0, // Far right
            0.0, -0.5, // Bottom

            //Bottom left triangle
            0, -0.5, // Top middle
            -0.2, -0.5, // Top left
            -0.28, -0.9, // Bottom left
            
            //Bottom right triangle
            0, -0.5, // Top middle
            0.2, -0.5, // Top right
            0.28, -0.9, // Bottom left
            ]
        );

        const state = compile(gl, vertexShaderSource, fragmentShaderSource);
        if (!state.program) {
            return state;
        }

        // ... how does that relate to the vertex buffer?
        initVertices(gl, state, "aPosition");

        return state;
    },
    generateControls: (gl, state, elements) => [{
        type: "renderButton",
        title: "Render",
        onClick: () => {
            gl.useProgram(state.program);

            // QUESTION: triangles?
            gl.drawArrays(gl.TRIANGLES, 0, 12);
        }
    }]
}
