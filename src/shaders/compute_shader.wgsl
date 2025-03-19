struct Particle {
    position: vec2<f32>,
    velocity: vec2<f32>,
};


@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;

// Constants
const MAX_PARTICLES_PER_LEAF: u32 = 10u;
const MAX_TREE_DEPTH: u32 = 6u;
const ROOT_NODE_INDEX: u32 = 0u;
const PERCEPTION_RADIUS: f32 = 0.1;
const MAX_SPEED: f32 = 0.02;
const MAX_FORCE: f32 = 0.005;
const BOUNDARY_LIMIT: f32 = 1.0;


// Compute shader for Boid Simulation using QuadTree
@compute @workgroup_size(256)
fn simulate_boids(@builtin(global_invocation_id) id: vec3<u32>) {
    let index: u32 = id.x;
    if index >= arrayLength(&particles) { return; }

    var p = particles[index];

    // Apply boundary conditions
    if abs(p.position.x) > BOUNDARY_LIMIT { p.velocity.x *= -1.0; }
    if abs(p.position.y) > BOUNDARY_LIMIT { p.velocity.y *= -1.0; }

    p.position += p.velocity;
    particles[index] = p;
}
