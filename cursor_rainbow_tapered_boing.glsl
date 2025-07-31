// Based on https://github.com/KroneCorylus/ghostty-shader-playground/blob/main/shaders/cursor_blaze_tapered.glsl
float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Based on Inigo Quilez's 2D distance functions article: https://iquilezles.org/articles/distfunctions2d/
// Potencially optimized by eliminating conditionals and loops to enhance performance and reduce branching

float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;
    return d;
}

float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float antialising(float distance) {
    return 1. - smoothstep(0., normalize(vec2(2., 2.), 0.).x, distance);
}

float determineStartVertexFactor(vec2 c, vec2 p) {
    // Conditions using step
    float condition1 = step(p.x, c.x) * step(c.y, p.y); // c.x < p.x && c.y > p.y
    float condition2 = step(c.x, p.x) * step(p.y, c.y); // c.x > p.x && c.y < p.y

    // If neither condition is met, return 1 (else case)
    return 1.0 - max(condition1, condition2);
}

float isLess(float c, float p) {
    // Conditions using step
    return 1.0 - step(p, c); // c < p
}

vec2 getRectangleCenter(vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.), rectangle.y - (rectangle.w / 2.));
}

float ease(float x) {
    return pow(1.0 - x, 3.0);
}

// Spring animation function with overshoot and bounce
float boingEase(float t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    
    // Parameters for spring animation
    float amplitude = 0.25;  // Overshoot amount
    float period = 0.25;    // Frequency of oscillation
    float decay = 7.0;      // How quickly oscillations decay
    
    // Create damped oscillation that settles at 1.0
    return 1.0 + amplitude * exp(-decay * t) * sin(2.0 * 3.14159 / period * t);
}

vec3 rainbow(float t) {
    t = fract(t);
    float r = abs(t * 6.0 - 3.0) - 1.0;
    float g = 2.0 - abs(t * 6.0 - 2.0);
    float b = 2.0 - abs(t * 6.0 - 4.0);
    return clamp(vec3(r, g, b), 0.0, 1.0);
}

const float DURATION = 0.3; //IN SECONDS - 250ms for spring effect

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif
    // Normalization for fragCoord to a space of -1 to 1;
    vec2 vu = normalize(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);

    // Normalization for cursor position and size;
    // cursor xy has the postion in a space of -1 to 1;
    // zw has the width and height
    vec4 currentCursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(normalize(iPreviousCursor.xy, 1.), normalize(iPreviousCursor.zw, 0.));

    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerCP = getRectangleCenter(previousCursor);
    
    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    float springProgress = boingEase(progress);
    
    // Interpolate cursor position with spring animation
    vec2 direction = centerCC - centerCP;
    vec2 animatedCenter = centerCP + direction * springProgress;
    
    // Create animated cursor based on spring position
    vec4 animatedCursor = vec4(
        animatedCenter.x - currentCursor.z * 0.5,
        animatedCenter.y + currentCursor.w * 0.5,
        currentCursor.z,
        currentCursor.w
    );
    
    // When drawing a parellelogram between cursors for the trail i need to determine where to start at the top-left or top-right vertex of the cursor
    float vertexFactor = determineStartVertexFactor(animatedCursor.xy, previousCursor.xy);
    float invertedVertexFactor = 1.0 - vertexFactor;

    float xFactor = isLess(previousCursor.x, animatedCursor.x);
    float yFactor = isLess(animatedCursor.y, previousCursor.y);

    // Set every vertex of my parellogram with tapering effect using animated cursor
    vec2 v0 = vec2(animatedCursor.x + animatedCursor.z * vertexFactor, animatedCursor.y - animatedCursor.w);
    vec2 v1 = vec2(animatedCursor.x + animatedCursor.z * xFactor, animatedCursor.y - animatedCursor.w * yFactor);
    vec2 v2 = vec2(animatedCursor.x + animatedCursor.z * invertedVertexFactor, animatedCursor.y);
    vec2 v3 = centerCP;

    float sdfCurrentCursor = getSdfRectangle(vu, animatedCursor.xy - (animatedCursor.zw * offsetFactor), animatedCursor.zw * 0.5);
    float sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);

    float easedProgress = ease(progress);
    // Distance between cursors determine the total length of the parallelogram;
    float lineLength = distance(animatedCenter, centerCP);

    // Rainbow colors based on time and position with spring animation influence
    float timeOffset = iTime * 0.5 + springProgress * 2.0;
    float positionOffset = (vu.x + vu.y) * 2.0;
    vec3 rainbowColor = rainbow(timeOffset + positionOffset);
    vec3 rainbowAccent = rainbow(timeOffset + positionOffset + 0.3);
    
    vec4 TRAIL_COLOR = vec4(rainbowColor, 1.0);
    vec4 TRAIL_COLOR_ACCENT = vec4(rainbowAccent, 1.0);

    vec4 newColor = vec4(fragColor);
    // Compute fade factor based on distance along the trail
    float fadeFactor = 1.0 - smoothstep(lineLength, sdfCurrentCursor, easedProgress * lineLength);

    float mod = .007;
    //trailblaze with rainbow colors
    vec4 trail = mix(TRAIL_COLOR_ACCENT, fragColor, 1. - smoothstep(0., sdfTrail + mod, 0.007));
    trail = mix(TRAIL_COLOR, trail, 1. - smoothstep(0., sdfTrail + mod, 0.006));
    trail = mix(trail, TRAIL_COLOR, step(sdfTrail + mod, 0.));
    //cursorblaze with rainbow colors
    trail = mix(TRAIL_COLOR_ACCENT, trail, 1. - smoothstep(0., sdfCurrentCursor + .002, 0.004));
    trail = mix(TRAIL_COLOR, trail, 1. - smoothstep(0., sdfCurrentCursor + .002, 0.004));
    fragColor = mix(trail, fragColor, 1. - smoothstep(0., sdfCurrentCursor, easedProgress * lineLength));
}
