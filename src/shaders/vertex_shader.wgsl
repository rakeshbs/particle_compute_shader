struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) velocity: vec2<f32>,
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    let boid_size: f32 = 0.009;
    
    // Use the instance data (position and velocity) from the current boid
    let position = input.position;
    let velocity = input.velocity;

    let angle: f32 = atan2(velocity.y, velocity.x);

    // Define triangle vertices relative to boid center
    var model_pos: vec2<f32>;
    switch (input.vertex_index) {
        case 0u: { model_pos = vec2<f32>(1.0, 0.0); } // Tip of triangle
        case 1u: { model_pos = vec2<f32>(-0.5, 0.3); } // Bottom left
        default: { model_pos = vec2<f32>(-0.5, -0.3); } // Bottom right
    }

    // Rotation matrix
    let cos_a = cos(angle);
    let sin_a = sin(angle);
    let rotation = mat2x2<f32>(
        cos_a, -sin_a,
        sin_a, cos_a
    );

    // Apply rotation and position for each boid
    let world_pos = position + (rotation * model_pos) * boid_size;

    var output: VertexOutput;
    output.clip_position = vec4<f32>(world_pos, 0.0, 1.0);
    
    // You could vary color based on velocity or other factors
    let speed = length(velocity) * 100.0; // Scale for visibility
    output.color = vec4<f32>(0.5 + speed, 0.5, 1.0 - speed, 1.0);

    return output;
}
