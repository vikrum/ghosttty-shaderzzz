float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

vec2 getRectangleCenter(vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.), rectangle.y - (rectangle.w / 2.));
}

float ease(float x) {
    return pow(1.0 - x, 3.0);
}

// Star shape SDF
float getSdfStar(vec2 p, float size) {
    // Create a 4-pointed star (plus shape)
    vec2 q = abs(p);
    float cross1 = max(q.x - size * 0.2, q.y - size);
    float cross2 = max(q.x - size, q.y - size * 0.2);
    return min(cross1, cross2);
}

// Random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Hash function for consistent randomness
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

const float DURATION = 2.0; // Trail duration in seconds
const int MAX_TRAILS = 20; // Maximum number of trail particles

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif
    
    vec2 vu = normalize(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);

    vec4 currentCursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(normalize(iPreviousCursor.xy, 1.), normalize(iPreviousCursor.zw, 0.));

    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerCP = getRectangleCenter(previousCursor);
    
    float sdfCurrentCursor = getSdfRectangle(vu, currentCursor.xy - (currentCursor.zw * offsetFactor), currentCursor.zw * 0.5);
    
    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress);
    
    // Movement vector
    vec2 movement = centerCC - centerCP;
    float movementLength = length(movement);
    
    vec4 result = fragColor;
    
    // Only create trails if there's movement
    if (movementLength > 0.01) {
        // Create multiple trail particles
        for (int i = 0; i < MAX_TRAILS; i++) {
            float particleId = float(i);
            
            // Use hash for consistent randomness per particle
            float randOffset = hash(particleId + iTimeCursorChange * 1000.0);
            float randX = hash(particleId * 2.0 + iTimeCursorChange * 1000.0) - 0.5;
            float randY = hash(particleId * 3.0 + iTimeCursorChange * 1000.0) - 0.5;
            
            // Stagger particle creation times
            float particleDelay = randOffset * 0.3;
            float particleProgress = clamp((progress - particleDelay) / 0.7, 0.0, 1.0);
            
            if (particleProgress > 0.0) {
                // Starting position along the trail path
                float pathPosition = randOffset;
                vec2 startPos = mix(centerCP, centerCC, pathPosition);
                
                // Add some random spread
                startPos += vec2(randX, randY) * 0.05;
                
                // Particle falls downward with gravity and drifts slightly
                float fallDistance = particleProgress * 0.3; // Fall amount (positive = downward)
                float drift = (randX * 0.1) * particleProgress; // Horizontal drift
                
                vec2 particlePos = startPos + vec2(drift, fallDistance);
                
                // Size decreases as it falls
                float initialSize = 0.008 + randOffset * 0.004;
                float currentSize = initialSize * (1.0 - particleProgress * 0.8);
                
                // Opacity fades as it falls
                float opacity = (1.0 - particleProgress) * 0.8;
                
                // Distance to particle
                float distToParticle = getSdfStar(vu - particlePos, currentSize);
                
                // Create the star effect
                float starMask = 1.0 - smoothstep(0.0, 0.002, distToParticle);
                
                // 15% chance for bright colors, otherwise monochrome
                float colorChance = hash(particleId * 5.0 + iTimeCursorChange * 1000.0);
                vec3 trailColor;
                
                if (colorChance < 0.15) {
                    // Random bright colors for 15% of particles
                    float hue = hash(particleId * 6.0 + iTimeCursorChange * 1000.0) * 6.28318; // 2*PI
                    vec3 brightColor = vec3(
                        0.5 + 0.5 * cos(hue),
                        0.5 + 0.5 * cos(hue + 2.094), // 2*PI/3
                        0.5 + 0.5 * cos(hue + 4.188)  // 4*PI/3
                    );
                    trailColor = brightColor;
                } else {
                    // Monochrome for contrast with background
                    vec3 bgColor = result.rgb;
                    float luminance = dot(bgColor, vec3(0.299, 0.587, 0.114));
                    trailColor = mix(vec3(1.0), vec3(0.0), step(0.5, luminance));
                }
                
                // Apply the trail
                result.rgb = mix(result.rgb, trailColor, starMask * opacity);
            }
        }
    }
    
    // Draw current cursor
    float cursorMask = 1.0 - smoothstep(0.0, 0.002, sdfCurrentCursor);
    vec3 bgColor = result.rgb;
    float luminance = dot(bgColor, vec3(0.299, 0.587, 0.114));
    vec3 cursorColor = mix(vec3(1.0), vec3(0.0), step(0.5, luminance));
    result.rgb = mix(result.rgb, cursorColor, cursorMask * 0.3);
    
    fragColor = result;
}
