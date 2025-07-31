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

// Hash function for consistent randomness
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// Smooth transition function
float smoothTransition(float t) {
    return t * t * (3.0 - 2.0 * t);
}

// Easing function for arriving at destination
float easeInOutCubic(float t) {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0;
}

// Rainbow color function
vec3 rainbow(float t) {
    t = fract(t);
    float r = abs(t * 6.0 - 3.0) - 1.0;
    float g = 2.0 - abs(t * 6.0 - 2.0);
    float b = 2.0 - abs(t * 6.0 - 4.0);
    return clamp(vec3(r, g, b), 0.0, 1.0);
}

const int NUM_BIRDS = 5;
const float ORBIT_RADIUS = 0.05;
const float FLIGHT_DURATION = 0.8; // Time to fly between positions
const float TRAIL_ALPHA_DECAY = 0.8; // Configurable alpha decay (closer to 1 = longer trails)
const float PIXEL_SIZE = 0.0125;

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
    
    float timeSinceMove = iTime - iTimeCursorChange;
    float flightProgress = clamp(timeSinceMove / FLIGHT_DURATION, 0.0, 1.0);
    float easedProgress = easeInOutCubic(flightProgress);
    
    vec4 result = fragColor;
    
    // Movement vector
    vec2 movement = centerCC - centerCP;
    float movementLength = length(movement);
    
    // Draw each bird
    for (int i = 0; i < NUM_BIRDS; i++) {
        float birdId = float(i);
        float birdOffset = birdId * 1.2566; // 2*PI / 5 for even spacing
        
        vec2 birdPos;
        
        if (movementLength < 0.001 || flightProgress >= 1.0) {
            // Orbiting current cursor position
            float orbitTime = iTime * 2.0 + birdOffset;
            birdPos = centerCC + vec2(
                cos(orbitTime) * ORBIT_RADIUS,
                sin(orbitTime) * ORBIT_RADIUS
            );
        } else {
            // Flying from previous to current position
            
            // Starting orbit position at previous cursor
            float startOrbitAngle = birdOffset;
            vec2 startPos = centerCP + vec2(
                cos(startOrbitAngle) * ORBIT_RADIUS,
                sin(startOrbitAngle) * ORBIT_RADIUS
            );
            
            // Target orbit position at current cursor
            float targetOrbitTime = iTime * 2.0 + birdOffset;
            vec2 targetPos = centerCC + vec2(
                cos(targetOrbitTime) * ORBIT_RADIUS,
                sin(targetOrbitTime) * ORBIT_RADIUS
            );
            
            // Create wavy bird-like flight path
            vec2 directPath = mix(startPos, targetPos, easedProgress);
            
            // Add wave motion perpendicular to flight direction
            vec2 flightDirection = normalize(targetPos - startPos);
            vec2 perpendicular = vec2(-flightDirection.y, flightDirection.x);
            
            // Wave parameters vary per bird for natural look
            float waveFreq = 8.0 + hash(birdId) * 4.0;
            float waveAmp = 0.02 + hash(birdId + 10.0) * 0.015;
            float wavePhase = hash(birdId + 20.0) * 6.28318;
            
            float waveOffset = sin(flightProgress * waveFreq + wavePhase) * waveAmp;
            // Dampen wave at start and end for smooth transitions
            waveOffset *= sin(flightProgress * 3.14159);
            
            birdPos = directPath + perpendicular * waveOffset;
        }
        
        // Draw bird pixel
        float distToBird = length(vu - birdPos);
        float birdMask = 1.0 - smoothstep(0.0, PIXEL_SIZE, distToBird);
        
        // Draw comet-like trail behind each bird with rainbow colors
        float numTrailSegments = 10.0;
        for (float trailStep = 1.0; trailStep <= numTrailSegments; trailStep++) {
            float trailTime = iTime - (trailStep * 0.09); // Look back in time (3x further)
            float trailTimeSinceMove = trailTime - iTimeCursorChange;
            float trailFlightProgress = clamp(trailTimeSinceMove / FLIGHT_DURATION, 0.0, 1.0);
            
            if (trailTimeSinceMove >= 0.0) { // Only draw if this time point is after cursor moved
                vec2 trailBirdPos;
                
                if (movementLength < 0.001 || trailFlightProgress >= 1.0) {
                    // Trail position when orbiting
                    float trailOrbitTime = trailTime * 2.0 + birdOffset;
                    trailBirdPos = centerCC + vec2(
                        cos(trailOrbitTime) * ORBIT_RADIUS,
                        sin(trailOrbitTime) * ORBIT_RADIUS
                    );
                } else {
                    // Trail position during flight
                    float trailEasedProgress = easeInOutCubic(trailFlightProgress);
                    
                    // Starting orbit position
                    float startOrbitAngle = birdOffset;
                    vec2 startPos = centerCP + vec2(
                        cos(startOrbitAngle) * ORBIT_RADIUS,
                        sin(startOrbitAngle) * ORBIT_RADIUS
                    );
                    
                    // Target position at trail time
                    float targetOrbitTime = trailTime * 2.0 + birdOffset;
                    vec2 targetPos = centerCC + vec2(
                        cos(targetOrbitTime) * ORBIT_RADIUS,
                        sin(targetOrbitTime) * ORBIT_RADIUS
                    );
                    
                    vec2 trailDirectPath = mix(startPos, targetPos, trailEasedProgress);
                    
                    // Add wave motion
                    vec2 flightDirection = normalize(targetPos - startPos);
                    vec2 perpendicular = vec2(-flightDirection.y, flightDirection.x);
                    
                    float waveFreq = 8.0 + hash(birdId) * 4.0;
                    float waveAmp = 0.02 + hash(birdId + 10.0) * 0.015;
                    float wavePhase = hash(birdId + 20.0) * 6.28318;
                    
                    float waveOffset = sin(trailFlightProgress * waveFreq + wavePhase) * waveAmp;
                    waveOffset *= sin(trailFlightProgress * 3.14159);
                    
                    trailBirdPos = trailDirectPath + perpendicular * waveOffset;
                }
                
                // Calculate rainbow color based on time and bird position
                float colorTime = iTime * 0.5 + birdId * 0.2 + trailStep * 0.1;
                vec3 trailColor = rainbow(colorTime);
                
                // Draw trail segment
                float distToTrail = length(vu - trailBirdPos);
                float trailAlpha = pow(TRAIL_ALPHA_DECAY, trailStep);
                float trailSize = PIXEL_SIZE * (1.0 - (trailStep / numTrailSegments) * 0.5); // Shrink trail
                float trailMask = 1.0 - smoothstep(0.0, trailSize, distToTrail);
                
                result.rgb = mix(result.rgb, trailColor, trailMask * trailAlpha);
            }
        }
        
        // Draw current bird position with white color
        result.rgb = mix(result.rgb, vec3(1.0), birdMask);
    }
    
    // Draw current cursor with slight transparency
    float cursorMask = 1.0 - smoothstep(0.0, 0.002, sdfCurrentCursor);
    result.rgb = mix(result.rgb, vec3(1.0), cursorMask * 0.2);
    
    fragColor = result;
}
