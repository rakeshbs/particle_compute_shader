struct Particle {
    position: vec2<f32>,
    velocity: vec2<f32>,
};


@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;

const MAX_SPEED: f32 = 0.005;
const BOUNDARY_LIMIT: f32 = 1.0;
const PERCEPTION_RADIUS: f32 = 0.09;

@compute @workgroup_size(256)
fn simulate_boids(@builtin(global_invocation_id) id: vec3<u32>) {
    let index: u32 = id.x;
    if index >= arrayLength(&particles) {
        return;
    }

    var p = particles[index]; // Current boid

    var alignment: vec2<f32> = vec2<f32>(0.0, 0.0);
    var cohesion: vec2<f32> = vec2<f32>(0.0, 0.0);
    var separation: vec2<f32> = vec2<f32>(0.0, 0.0);

    var total: u32 = 0u;

    for (var k: u32 = 0u; k < arrayLength(&particles); k = k + 1u) {
        if k == index {
            continue;
        }

        let neighbor = particles[k];
        let distance = length(p.position - neighbor.position);
        if abs(distance) < PERCEPTION_RADIUS {
            alignment += neighbor.velocity;

            if distance > 0.01 && distance < PERCEPTION_RADIUS {
                separation += (p.position - neighbor.position) / (distance * distance); // Inverse square falloff
            }

            cohesion += neighbor.position;
            total += 1u;
        }
    }

    if total > 0u {
        let total_f32: f32 = f32(total);
        alignment /= total_f32;
        cohesion /= total_f32;
        separation /= total_f32;
        p.velocity += normalize(alignment) * 0.001;
        p.velocity += normalize(cohesion - p.position) * 0.002;
        p.velocity += normalize(separation) * 0.0023;
    }

    let speed = length(p.velocity);
    if speed > 0.0001 {
        p.velocity = normalize(p.velocity) * min(speed, MAX_SPEED);
    } else {
        p.velocity = vec2<f32>(0.001, 0.001); // Ensures the particle keeps moving
    }

    p.position += p.velocity;

    if abs(p.position.x) > BOUNDARY_LIMIT || abs(p.position.y) > BOUNDARY_LIMIT {
        p.velocity = -p.velocity;
    }
    if abs(p.position.x) > BOUNDARY_LIMIT {
        p.position.x = sign(p.position.x) * BOUNDARY_LIMIT;
    }


    particles[index] = p;
}
