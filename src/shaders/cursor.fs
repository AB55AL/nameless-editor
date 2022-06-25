#version 330 core
out vec4 FragColor;

uniform vec3 cursorColor; // the input variable from the vertex shader (same name and same type)  

void main() {
  FragColor = vec4(cursorColor, 0.0);
} 
