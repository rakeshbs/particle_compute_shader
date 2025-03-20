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
    // Get position and velocity for this instance
    let position = input.position;
    let velocity = input.velocity;
    
    // Normalize the velocity to get the direction vector
    let speed = length(velocity);
    // Prevent division by zero
    let direction = select(
        vec2<f32>(1.0, 0.0),  // Default direction if velocity is zero
        velocity / speed,      // Normalized velocity
        speed > 0.00001        // Condition: only normalize if speed is non-zero
    );
    
    // Size of the triangle
    let boid_size: f32 = 0.009;
    
    // Define triangle vertices explicitly in local space
    // Tip of triangle pointing toward positive X
    var local_pos: vec2<f32>;
    switch (input.vertex_index) {
        case 0u: { local_pos = vec2<f32>(1.0, 0.0); }  // Tip
        case 1u: { local_pos = vec2<f32>(-0.5, 0.5); } // Back left
        case 2u: { local_pos = vec2<f32>(-0.5, -0.5); } // Back right
        default: { local_pos = vec2<f32>(0.0, 0.0); }  // Fallback
    }
    
    // Manual rotation calculation - rotate to align with velocity
    // This is clearer than using a rotation matrix for debugging
    var rotated_pos: vec2<f32>;
    if speed > 0.00001 {
        // If we have a non-zero velocity, align with it
        if input.vertex_index == 0u {
            // Tip of triangle - place in direction of velocity
            rotated_pos = direction * boid_size;
        } else if input.vertex_index == 1u {
            // Back left - perpendicular to velocity, plus backward
            rotated_pos = vec2<f32>(
                -direction.x * 0.5 - direction.y * 0.5,
                -direction.y * 0.5 + direction.x * 0.5
            ) * boid_size;
        } else {
            // Back right - perpendicular to velocity, minus backward
            rotated_pos = vec2<f32>(
                -direction.x * 0.5 + direction.y * 0.5,
                -direction.y * 0.5 - direction.x * 0.5
            ) * boid_size;
        }
    } else {
        // Fallback for zero velocity - just scale the local position
        rotated_pos = local_pos * boid_size;
    }
    
    // Apply the final position
    let world_pos = position + rotated_pos;

    var output: VertexOutput;
    output.clip_position = vec4<f32>(world_pos, 0.0, 1.0);
    
    // Debug coloring to see velocity direction:
    // - Red component shows x velocity
    // - Green component shows y velocity
    // - Blue shows overall speed
    output.color = vec4<f32>(
        abs(direction.x),
        abs(direction.y),
        speed * 100.0,  // Scale speed for visibility
        1.0
    );

    return output;
}
