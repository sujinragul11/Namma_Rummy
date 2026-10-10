'use strict';
// Makes every sound in godot/audio/ from arithmetic alone: no samples and no recordings,
// so there is nothing to license. To change a sound, edit its recipe below and run:
//
//   node tools/make_audio.js              every file
//   node tools/make_audio.js win tick     only these
//   node tools/make_audio.js --report     also print the length and loudness of each
//
// Then open the project in the Godot editor once (or run `godot --path . --import`) so the
// changed files are imported. To use a recording instead, replace the .wav and keep its name.

const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, '..', 'audio');
const SR = 44100; // sound effects, mono
const MUSIC_SR = 32000; // music, stereo
const TAU = Math.PI * 2;

// ---------- small helpers ----------

// A repeatable random source, so a sound comes out the same on every run.
function rngFrom(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const SEMITONES = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

// "A4" -> 440, "C#5" -> 554.37
function hz(name) {
  const m = /^([A-G])(#?)(-?\d)$/.exec(name);
  if (!m) throw new Error(`not a note: ${name}`);
  const midi = SEMITONES[m[1]] + (m[2] ? 1 : 0) + (Number(m[3]) + 1) * 12;
  return 440 * 2 ** ((midi - 69) / 12);
}

const clamp01 = (x) => Math.min(1, Math.max(0, x));
const decay = (t, tau) => Math.exp(-t / tau);
const attack = (t, seconds) => (t < seconds ? t / seconds : 1);
// Rises and falls once over `seconds`.
const swell = (t, seconds) => Math.sin(Math.PI * clamp01(t / seconds)) ** 2;
// Moves from one pitch to another along a musical (exponential) curve.
const glide = (from, to, t, seconds) => from * (to / from) ** clamp01(t / seconds);
// 1 until `seconds` before the end, then down to 0: stops a note without a click.
const release = (t, length, seconds) => clamp01((length - t) / seconds);

function tone(seconds, fn, sr = SR) {
  const out = new Float64Array(Math.ceil(seconds * sr));
  for (let i = 0; i < out.length; i++) out[i] = fn(i / sr);
  return out;
}

function mix(target, source, atSeconds = 0, gain = 1, sr = SR) {
  const at = Math.round(atSeconds * sr);
  for (let i = 0; i < source.length && at + i < target.length; i++) target[at + i] += source[i] * gain;
  return target;
}

const silence = (seconds, sr = SR) => new Float64Array(Math.ceil(seconds * sr));

// A filter whose cutoff can move while it runs (Cytomic's state-variable filter).
class Svf {
  constructor(sr) {
    this.sr = sr;
    this.a = 0;
    this.b = 0;
    this.lp = 0;
    this.bp = 0;
    this.hp = 0;
  }

  step(x, cutoff, q) {
    const g = Math.tan((Math.PI * Math.min(cutoff, this.sr * 0.45)) / this.sr);
    const k = 1 / q;
    const a1 = 1 / (1 + g * (g + k));
    const a2 = g * a1;
    const v3 = x - this.b;
    const v1 = a1 * this.a + a2 * v3;
    const v2 = this.b + a2 * this.a + g * a2 * v3;
    this.a = 2 * v1 - this.a;
    this.b = 2 * v2 - this.b;
    this.lp = v2;
    this.bp = v1;
    this.hp = x - k * v1 - v2;
  }
}

// Noise through a filter; `cutoff` and `amp` are functions of time. `band` is lp, bp or hp.
function noise(seconds, rng, cutoff, q, amp, band = 'bp', sr = SR) {
  const filter = new Svf(sr);
  return tone(seconds, (t) => {
    filter.step(rng() * 2 - 1, cutoff(t), q);
    return filter[band] * amp(t);
  }, sr);
}

// A sine whose pitch may move.
function sine(seconds, freq, amp, sr = SR) {
  let phase = 0;
  return tone(seconds, (t) => {
    phase += (TAU * freq(t)) / sr;
    return Math.sin(phase) * amp(t);
  }, sr);
}

// A sawtooth without the harsh digital edge (PolyBLEP).
class Saw {
  constructor(sr) {
    this.sr = sr;
    this.phase = 0;
  }

  step(freq) {
    const dt = freq / this.sr;
    this.phase += dt;
    if (this.phase >= 1) this.phase -= 1;
    let p = this.phase;
    let blep = 0;
    if (p < dt) {
      p /= dt;
      blep = p + p - p * p - 1;
    } else if (p > 1 - dt) {
      p = (p - 1) / dt;
      blep = p * p + p + p + 1;
    }
    return 2 * this.phase - 1 - blep;
  }
}

// The room around a sound (Freeverb). `process` returns only the echo, not the dry signal.
class Reverb {
  constructor(sr, room = 0.82, damp = 0.25, spread = 0) {
    const scale = sr / 44100;
    this.room = room;
    this.damp = damp;
    this.combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((n) => ({
      line: new Float64Array(Math.round((n + spread) * scale)),
      at: 0,
      store: 0,
    }));
    this.passes = [556, 441, 341, 225].map((n) => ({
      line: new Float64Array(Math.round((n + spread) * scale)),
      at: 0,
    }));
  }

  process(x) {
    const input = x * 0.015;
    let out = 0;
    for (const comb of this.combs) {
      const y = comb.line[comb.at];
      comb.store = y * (1 - this.damp) + comb.store * this.damp;
      comb.line[comb.at] = input + comb.store * this.room;
      comb.at = (comb.at + 1) % comb.line.length;
      out += y;
    }
    for (const pass of this.passes) {
      const y = pass.line[pass.at];
      pass.line[pass.at] = out + y * 0.5;
      pass.at = (pass.at + 1) % pass.line.length;
      out = y - out;
    }
    return out;
  }
}

// Adds a room to a mono sound. `wet` is how much echo, 0 to 1.
function inRoom(dry, wet, tailSeconds = 0.8, room = 0.8, sr = SR) {
  const reverb = new Reverb(sr, room);
  const out = new Float64Array(dry.length + Math.ceil(tailSeconds * sr));
  for (let i = 0; i < out.length; i++) {
    const x = i < dry.length ? dry[i] : 0;
    out[i] = x + reverb.process(x) * wet * 3;
  }
  return out;
}

// ---------- instruments ----------

// A struck metal bar: glockenspiel, or a small bell.
function chime(freq, seconds, sr = SR, bright = 1) {
  return tone(seconds, (t) => attack(t, 0.002) * (
    Math.sin(TAU * freq * t) * decay(t, 0.38)
    + 0.35 * bright * Math.sin(TAU * freq * 2.76 * t) * decay(t, 0.12)
    + 0.16 * bright * Math.sin(TAU * freq * 5.4 * t) * decay(t, 0.05)
  ), sr);
}

// A struck wooden bar.
function marimba(freq, seconds, sr = SR) {
  return tone(seconds, (t) => attack(t, 0.002) * (
    Math.sin(TAU * freq * t) * decay(t, 0.16)
    + 0.3 * Math.sin(TAU * freq * 4 * t) * decay(t, 0.04)
    + 0.08 * Math.sin(TAU * freq * 10 * t) * decay(t, 0.012)
  ), sr);
}

// Trumpets: two sawtooths a little apart, opening up as the note starts.
function brass(freq, seconds, sr = SR, vibrato = 0) {
  const saws = [new Saw(sr), new Saw(sr)];
  const filter = new Svf(sr);
  return tone(seconds, (t) => {
    const wobble = 1 + vibrato * 0.006 * Math.sin(TAU * 5.5 * t) * clamp01((t - 0.3) / 0.3);
    const x = saws[0].step(freq * 1.0025 * wobble) + saws[1].step(freq * 0.9975 * wobble);
    filter.step(x, 500 + 2600 * attack(t, 0.05) * (0.55 + 0.45 * decay(t, 0.25)), 0.9);
    return filter.lp * 0.5 * attack(t, 0.02) * (0.75 + 0.25 * decay(t, 0.15)) * release(t, seconds, 0.08);
  }, sr);
}

// An electric piano (two-operator FM): a bell-like start that settles into a soft tone.
function epiano(freq, seconds, sr = SR, force = 1) {
  const tineHz = freq * 14 < sr * 0.45 ? freq * 14 : 0;
  return tone(seconds + 0.15, (t) => {
    const index = 1.5 * force * decay(t, 0.5) + 0.25;
    const body = Math.sin(TAU * freq * t + index * Math.sin(TAU * freq * t));
    const tine = Math.sin(TAU * tineHz * t) * decay(t, 0.03) * 0.25 * force;
    return (body + tine) * attack(t, 0.004) * decay(t, 1.4) * release(t, seconds + 0.15, 0.15);
  }, sr);
}

// A vibraphone: a pure note with a slow wobble in its loudness.
function vibes(freq, seconds, sr = SR) {
  return tone(seconds + 0.25, (t) => {
    const wobble = 1 - 0.28 * (0.5 + 0.5 * Math.sin(TAU * 5.2 * t));
    return attack(t, 0.003) * release(t, seconds + 0.25, 0.25) * (
      Math.sin(TAU * freq * t) * decay(t, 1.2) * wobble
      + 0.25 * Math.sin(TAU * freq * 4 * t) * decay(t, 0.08)
      + 0.06 * Math.sin(TAU * freq * 10 * t) * decay(t, 0.02)
    );
  }, sr);
}

// A plucked bass: a sawtooth and a sine under a filter that closes after the pluck.
function bass(freq, seconds, sr = SR) {
  const saw = new Saw(sr);
  const filter = new Svf(sr);
  return tone(seconds, (t) => {
    filter.step(saw.step(freq) * 0.6, 240 + 800 * decay(t, 0.12), 0.8);
    const x = filter.lp + 0.6 * Math.sin(TAU * freq * t);
    return x * attack(t, 0.006) * (0.55 + 0.45 * decay(t, 0.3)) * release(t, seconds, 0.05);
  }, sr);
}

// A plucked nylon string (Karplus-Strong): a burst of noise going round a delay that is as
// long as one cycle of the note, losing a little brightness on every pass.
function pluck(freq, seconds, rng, sr = SR, damping = 0.996) {
  const delay = sr / freq - 0.5; // the averaging below adds the other half sample
  const whole = Math.floor(delay);
  const part = delay - whole;
  const line = new Float64Array(whole + 2);
  const out = new Float64Array(Math.ceil(seconds * sr));
  let soft = 0;
  let previous = 0;
  let body = 0;
  let bodyBefore = 0;
  let level = 0;
  const keep = 1 - (TAU * 30) / sr; // lets everything above 30 Hz through
  for (let i = 0; i < out.length; i++) {
    const at = i % line.length;
    const older = line[(at + 1) % line.length]; // written whole + 1 samples ago
    const newer = line[(at + 2) % line.length]; // written whole samples ago
    const read = newer * (1 - part) + older * part;
    let x = damping * 0.5 * (read + previous);
    previous = read;
    if (i < whole) {
      soft += 0.45 * (rng() * 2 - 1 - soft); // the pluck itself, with the edge taken off
      x += soft;
    }
    line[at] = x;
    body += 0.5 * (x - body);
    // The noise burst is never perfectly balanced; without this the string would sit off-centre
    level = body - bodyBefore + keep * level;
    bodyBefore = body;
    out[i] = level * release(i / sr, seconds, 0.04);
  }
  return out;
}

// A flute: nearly a pure tone, with breath in it and a slow vibrato once the note is held.
function flute(freq, seconds, rng, sr = SR) {
  const breath = new Svf(sr);
  let phase = 0;
  return tone(seconds, (t) => {
    const vibrato = 1 + 0.006 * Math.sin(TAU * 5.2 * t) * clamp01((t - 0.18) / 0.2);
    phase += (TAU * freq * vibrato) / sr;
    breath.step(rng() * 2 - 1, freq * 2, 3);
    const x = Math.sin(phase) + 0.28 * Math.sin(2 * phase) + 0.08 * Math.sin(3 * phase);
    const air = breath.bp * (0.05 + 0.2 * decay(t, 0.05));
    return (x + air) * 0.6 * (0.5 - 0.5 * Math.cos(Math.PI * attack(t, 0.06))) * release(t, seconds, 0.09);
  }, sr);
}

// Soft strings: three sawtooths a little apart, fading in slowly.
function strings(freq, seconds, sr = SR) {
  const saws = [new Saw(sr), new Saw(sr), new Saw(sr)];
  const filter = new Svf(sr);
  return tone(seconds + 0.5, (t) => {
    const x = saws[0].step(freq * 0.996) + saws[1].step(freq) + saws[2].step(freq * 1.004);
    filter.step(x, 600 + 500 * attack(t, 0.4), 0.7);
    return filter.lp * 0.33 * attack(t, 0.3) * release(t, seconds + 0.5, 0.5);
  }, sr);
}

const drums = {
  kick: (sr) => sine(0.4, (t) => 45 + 75 * decay(t, 0.03), (t) => attack(t, 0.002) * decay(t, 0.13), sr),
  rim: (sr, rng) => mix(
    tone(0.08, (t) => 0.5 * Math.sin(TAU * 1700 * t) * decay(t, 0.012) + 0.4 * Math.sin(TAU * 480 * t) * decay(t, 0.02), sr),
    noise(0.05, rng, () => 2600, 3, (t) => decay(t, 0.008), 'bp', sr), 0, 1, sr),
  hat: (sr, rng) => noise(0.12, rng, () => 7000, 0.8, (t) => attack(t, 0.001) * decay(t, 0.018), 'hp', sr),
  foot: (sr, rng) => noise(0.2, rng, () => 5000, 0.8, (t) => attack(t, 0.002) * decay(t, 0.035), 'hp', sr),
  shaker: (sr, rng) => noise(0.16, rng, () => 6500, 1.5, (t) => attack(t, 0.012) * decay(t, 0.03), 'bp', sr),
  ride: (sr, rng) => mix(
    tone(1.0, (t) => {
      let x = 0;
      for (const partial of [3170, 4130, 5210, 6480, 7730]) x += Math.sin(TAU * partial * t);
      return x * 0.2 * attack(t, 0.001) * decay(t, 0.22);
    }, sr),
    noise(0.4, rng, () => 6000, 0.8, (t) => decay(t, 0.07), 'hp', sr), 0, 0.5, sr),
};

// ---------- card and table sounds ----------

// A card leaving the deck: a short breath of noise that falls in pitch.
function cardSlide(rng, seconds = 0.13, bright = 1) {
  return noise(seconds, rng, (t) => glide(3800 * bright, 1400 * bright, t, seconds), 1.2,
    (t) => attack(t, 0.008) * decay(t, 0.035) * 0.9);
}

// A card landing: a click with a little weight under it.
function cardTap(rng, weight = 1) {
  const out = silence(0.09);
  mix(out, noise(0.03, rng, () => 2500, 2, (t) => decay(t, 0.004) * 0.9));
  mix(out, sine(0.09, (t) => glide(220, 120, t, 0.05), (t) => attack(t, 0.001) * decay(t, 0.018) * 0.8 * weight));
  mix(out, noise(0.08, rng, () => 900, 0.8, (t) => decay(t, 0.02) * 0.5 * weight, 'lp'));
  return out;
}

// A row of chime notes, each starting `gap` seconds after the one before.
function arpeggio(notes, gap, noteSeconds, voice = chime) {
  const out = silence(gap * (notes.length - 1) + noteSeconds);
  notes.forEach((name, index) => mix(out, voice(hz(name), noteSeconds), gap * index, 0.6));
  return out;
}

// A scatter of tiny high notes: glitter.
function glitter(rng, seconds, grains, loudness = 0.1) {
  const out = silence(seconds + 0.15);
  for (let k = 0; k < grains; k++) {
    const at = rng() * seconds;
    const freq = 3500 + rng() * 4500;
    mix(out, tone(0.12, (t) => Math.sin(TAU * freq * t) * attack(t, 0.002) * decay(t, 0.03)), at,
      loudness * (1 - (0.6 * at) / seconds));
  }
  return out;
}

const sounds = {
  // Dealing and drawing
  card: () => cardSlide(rngFrom(11)),
  place: () => cardTap(rngFrom(12)),
  flip: () => {
    const rng = rngFrom(13);
    return mix(mix(silence(0.16), cardSlide(rng, 0.07, 1.3), 0, 0.7), cardTap(rng, 0.6), 0.07, 0.8);
  },
  shuffle: () => {
    // A riffle (clicks coming faster and faster), the cards pushed together, the deck set down
    const rng = rngFrom(14);
    const out = silence(1.0);
    let at = 0.02;
    for (let k = 0; at < 0.56; k++) {
      const band = 2000 + rng() * 3000;
      const loud = (0.3 + rng() * 0.5) * (0.5 + 0.5 * swell(at, 0.6));
      mix(out, noise(0.02, rng, () => band, 2.5, (t) => decay(t, 0.003) * loud), at);
      at += 0.028 - 0.019 * clamp01(k / 30) + rng() * 0.003;
    }
    mix(out, noise(0.26, rng, (t) => glide(800, 2600, t, 0.26), 1.5, (t) => swell(t, 0.26) * 0.35), 0.6);
    mix(out, cardTap(rng, 1.2), 0.88);
    return out;
  },
  group: () => {
    const rng = rngFrom(15);
    const out = silence(0.22);
    mix(out, cardSlide(rng, 0.08, 1.1), 0, 0.6);
    mix(out, cardSlide(rng, 0.08, 0.9), 0.05, 0.6);
    return mix(out, cardTap(rng), 0.12);
  },

  // Fingers on the screen
  select: () => sine(0.12, (t) => glide(700, 1050, t, 0.05),
    (t) => attack(t, 0.002) * decay(t, 0.035) * 0.8),
  deselect: () => sine(0.12, (t) => glide(900, 600, t, 0.05),
    (t) => attack(t, 0.002) * decay(t, 0.035) * 0.6),
  click: () => {
    const rng = rngFrom(16);
    const out = tone(0.09, (t) => attack(t, 0.001) * (
      Math.sin(TAU * glide(440, 330, t, 0.04) * t) * decay(t, 0.025)
      + 0.3 * Math.sin(TAU * 1180 * t) * decay(t, 0.01)));
    return mix(out, noise(0.01, rng, () => 4000, 1, (t) => decay(t, 0.002) * 0.4, 'hp'));
  },
  whoosh: () => {
    const rng = rngFrom(17);
    return noise(0.5, rng, (t) => (t < 0.27 ? glide(400, 2600, t, 0.27) : glide(2600, 900, t - 0.27, 0.23)), 2.5,
      (t) => swell(t, 0.5) * 0.7);
  },

  // Turns and the clock
  turn: () => inRoom(arpeggio(['G5', 'C6', 'E6'], 0.13, 0.7), 0.2),
  pass: () => marimba(hz('C5'), 0.25),
  tick: () => {
    const rng = rngFrom(18);
    const out = tone(0.07, (t) => Math.sin(TAU * 2000 * t) * decay(t, 0.008) * 0.6
      + Math.sin(TAU * 900 * t) * decay(t, 0.015) * 0.5);
    return mix(out, noise(0.01, rng, () => 5000, 1, (t) => decay(t, 0.0015) * 0.5, 'hp'));
  },
  beep: () => tone(0.14, (t) => (Math.sin(TAU * 880 * t) + 0.2 * Math.sin(TAU * 1760 * t))
    * attack(t, 0.004) * release(t, 0.14, 0.06) * 0.7),
  go: () => inRoom(tone(0.45, (t) => (Math.sin(TAU * 1320 * t) + 0.5 * Math.sin(TAU * 1980 * t))
    * attack(t, 0.004) * decay(t, 0.14) * 0.6), 0.15, 0.4),

  // Melds
  meld: () => {
    const rng = rngFrom(19);
    const out = mix(silence(0.9), arpeggio(['C6', 'E6', 'G6', 'C7'], 0.05, 0.6));
    return inRoom(mix(out, glitter(rng, 0.4, 12), 0.2), 0.25);
  },
  meld_pure: () => {
    const rng = rngFrom(20);
    const out = mix(silence(1.1), arpeggio(['C6', 'E6', 'G6', 'C7', 'E7', 'G7'], 0.045, 0.7));
    mix(out, chime(hz('C5'), 0.8), 0, 0.4);
    return inRoom(mix(out, glitter(rng, 0.55, 22, 0.12), 0.25), 0.3, 1.0);
  },
  sparkle: () => inRoom(glitter(rngFrom(21), 0.5, 16, 0.3), 0.3),

  // Messages
  notice: () => tone(0.14, (t) => {
    const f = glide(500, 800, t, 0.06);
    return (Math.sin(TAU * f * t) + 0.2 * Math.sin(TAU * 2 * f * t)) * attack(t, 0.003) * decay(t, 0.045) * 0.8;
  }),
  warning: () => arpeggio(['A5', 'E5'], 0.12, 0.3, marimba),
  error: () => {
    // A buzzer: two notes almost in tune, so they grind against each other
    const saws = [new Saw(SR), new Saw(SR)];
    const filter = new Svf(SR);
    return tone(0.34, (t) => {
      filter.step(saws[0].step(140) + saws[1].step(147), 900, 0.8);
      const on = t < 0.12 ? swell(t, 0.12) ** 0.2 : swell(t - 0.15, 0.19) ** 0.2;
      return filter.lp * 0.5 * (t > 0.12 && t < 0.15 ? 0 : on);
    });
  },
  join: () => arpeggio(['C5', 'G5'], 0.1, 0.3, marimba),
  leave: () => arpeggio(['G5', 'C5'], 0.1, 0.3, marimba),
  count: () => tone(0.04, (t) => (Math.sin(TAU * 1500 * t) + 0.3 * Math.sin(TAU * 3000 * t))
    * attack(t, 0.001) * decay(t, 0.006) * 0.7),

  // The end of a round
  declare: () => {
    // A rush of air, then a heavy hit with an open chord ringing over it
    const rng = rngFrom(22);
    const out = silence(1.5);
    mix(out, noise(0.3, rng, (t) => glide(500, 6000, t, 0.3), 2, (t) => (t / 0.3) ** 3 * 0.5));
    mix(out, sine(1.1, (t) => glide(110, 38, t, 0.35), (t) => attack(t, 0.003) * decay(t, 0.35) * 0.9), 0.3);
    mix(out, noise(0.9, rng, (t) => glide(1500, 200, t, 0.5), 0.7, (t) => decay(t, 0.22) * 0.6, 'lp'), 0.3);
    for (const name of ['C3', 'G3', 'C4', 'G4']) {
      const saw = new Saw(SR);
      const filter = new Svf(SR);
      mix(out, tone(1.1, (t) => {
        filter.step(saw.step(hz(name)), 2500 * decay(t, 0.4) + 300, 0.8);
        return filter.lp * attack(t, 0.004) * decay(t, 0.45);
      }), 0.3, 0.14);
    }
    return inRoom(out, 0.3, 1.0, 0.86);
  },
  win: () => {
    // A fanfare: a run up the C major chord, two pick-up notes, then the whole chord held
    const rng = rngFrom(23);
    const out = silence(2.7);
    const run = [['G4', 0, 0.1], ['C5', 0.11, 0.1], ['E5', 0.22, 0.1], ['G5', 0.33, 0.3], ['E5', 0.66, 0.1], ['G5', 0.77, 0.11]];
    for (const [name, at, length] of run) {
      mix(out, brass(hz(name), length), at, 0.5);
      mix(out, chime(hz(name) * 2, 0.4), at, 0.12);
    }
    for (const name of ['C4', 'E4', 'G4', 'C5', 'E5', 'G5']) mix(out, brass(hz(name), 1.7, SR, 1), 0.9, 0.17);
    mix(out, brass(hz('C6'), 1.7, SR, 1), 0.9, 0.3);
    mix(out, brass(hz('C3'), 0.8), 0, 0.2);
    mix(out, brass(hz('C3'), 1.7), 0.9, 0.3);
    mix(out, drums.kick(SR), 0.9, 0.7);
    mix(out, noise(1.7, rng, () => 5000, 0.7, (t) => attack(t, 0.004) * decay(t, 0.5) * 0.25, 'hp'), 0.9);
    mix(out, arpeggio(['C6', 'E6', 'G6', 'C7', 'E7', 'G7', 'C8'], 0.07, 0.6), 1.0, 0.35);
    mix(out, glitter(rng, 1.0, 30, 0.08), 1.2);
    return inRoom(out, 0.28, 1.0, 0.84);
  },
  lose: () => {
    // Three soft notes stepping down an A minor chord, then the chord itself, growing dim
    const out = silence(2.2);
    for (const [name, at] of [['E5', 0], ['C5', 0.26], ['A4', 0.52]]) mix(out, epiano(hz(name), 0.3), at, 0.5);
    for (const name of ['A3', 'C4', 'E4']) mix(out, epiano(hz(name), 1.3, SR, 0.5), 0.8, 0.3);
    mix(out, sine(1.3, () => hz('A2'), (t) => attack(t, 0.02) * decay(t, 0.5) * 0.4), 0.8);
    const filter = new Svf(SR);
    const dimmed = tone(2.2, (t) => {
      filter.step(out[Math.floor(t * SR)], glide(4000, 500, t, 2.0), 0.7);
      return filter.lp;
    });
    return inRoom(dimmed, 0.25, 0.9);
  },
  drop: () => {
    const rng = rngFrom(24);
    const out = sine(0.5, (t) => glide(900, 180, t, 0.45) * (1 + 0.03 * Math.sin(TAU * 14 * t)),
      (t) => swell(t, 0.5) * 0.6);
    mix(out, noise(0.45, rng, (t) => glide(3000, 500, t, 0.45), 1.5, (t) => swell(t, 0.45) * 0.3));
    const whole = mix(silence(0.62), out);
    return mix(whole, cardTap(rng, 1.4), 0.48);
  },
  wrong: () => {
    // Two rude notes, the second a tritone below the first and sagging
    const out = silence(0.85);
    for (const [name, at, length, sag] of [['G3', 0, 0.16, 1], ['C#3', 0.2, 0.6, 0.94]]) {
      const saws = [new Saw(SR), new Saw(SR)];
      const filter = new Svf(SR);
      mix(out, tone(length, (t) => {
        const f = glide(hz(name), hz(name) * sag, t, length);
        filter.step(saws[0].step(f) + saws[1].step(f * 1.01), glide(1800, 500, t, length), 1.2);
        return filter.lp * 0.4 * attack(t, 0.006) * release(t, length, 0.05);
      }), at);
    }
    return out;
  },

  // Celebration
  firework: () => {
    // The bang, then the crackle as the sparks burn out
    const rng = rngFrom(25);
    const out = silence(1.3);
    mix(out, sine(0.4, (t) => glide(150, 50, t, 0.15), (t) => attack(t, 0.002) * decay(t, 0.12) * 0.9));
    mix(out, noise(0.5, rng, () => 1800, 0.7, (t) => attack(t, 0.002) * decay(t, 0.1) * 0.7));
    for (let k = 0; k < 70; k++) {
      const at = 0.08 + rng() ** 1.6 * 1.0;
      const band = 3000 + rng() * 5000;
      const loud = (0.15 + rng() * 0.35) * (1 - at / 1.2);
      mix(out, noise(0.012, rng, () => band, 1.5, (t) => decay(t, 0.002) * loud, 'hp'), at);
    }
    return inRoom(out, 0.2, 0.6);
  },
  confetti: () => {
    const rng = rngFrom(26);
    const out = silence(0.55);
    mix(out, noise(0.12, rng, () => 800, 0.8, (t) => attack(t, 0.001) * decay(t, 0.025) * 0.9, 'hp'));
    mix(out, sine(0.12, (t) => glide(300, 150, t, 0.06), (t) => decay(t, 0.03) * 0.7));
    mix(out, noise(0.5, rng, () => 4000, 0.8, (t) => attack(t, 0.01) * decay(t, 0.2) * 0.15, 'hp'), 0.02);
    return mix(out, glitter(rng, 0.35, 8, 0.07), 0.05);
  },
};

// ---------- music ----------

// A piece of music being put together: notes are placed on a beat, and at the end the
// part that rings past the last bar is folded back onto the start so the loop has no seam.
class Song {
  constructor(bpm, beats) {
    this.sr = MUSIC_SR;
    this.beatSeconds = 60 / bpm;
    this.loop = Math.round(beats * this.beatSeconds * this.sr);
    const length = this.loop + 6 * this.sr;
    this.left = new Float64Array(length);
    this.right = new Float64Array(length);
    this.send = new Float64Array(length); // what goes to the reverb
    this.loudness = {}; // per part, for --report
    this.rng = rngFrom(Math.round(bpm * 1000 + beats));
    this.cache = new Map();
  }

  // Builds each different note once.
  note(key, build) {
    if (!this.cache.has(key)) this.cache.set(key, build());
    return this.cache.get(key);
  }

  // `pan` runs from -1 (left) to 1 (right); `room` is how much of the note goes to the reverb.
  add(part, samples, beat, gain, pan = 0, room = 0.15) {
    const at = Math.max(0, Math.round(beat * this.beatSeconds * this.sr));
    const l = gain * Math.cos(((pan + 1) * Math.PI) / 4);
    const r = gain * Math.sin(((pan + 1) * Math.PI) / 4);
    let energy = 0;
    for (let i = 0; i < samples.length && at + i < this.left.length; i++) {
      const s = samples[i];
      this.left[at + i] += s * l;
      this.right[at + i] += s * r;
      this.send[at + i] += s * gain * room;
      energy += s * s * gain * gain;
    }
    this.loudness[part] = (this.loudness[part] || 0) + energy;
  }

  // A little unevenness in how hard a note is played, as a person would.
  touch(amount = 0.15) {
    return 1 - amount + this.rng() * amount * 2;
  }

  finish(peak = 0.89) {
    const rooms = [new Reverb(this.sr, 0.8, 0.3, 0), new Reverb(this.sr, 0.8, 0.3, 23)];
    for (let i = 0; i < this.left.length; i++) {
      this.left[i] += rooms[0].process(this.send[i]) * 3;
      this.right[i] += rooms[1].process(this.send[i]) * 3;
    }
    for (let i = this.loop; i < this.left.length; i++) {
      this.left[i - this.loop] += this.left[i];
      this.right[i - this.loop] += this.right[i];
    }
    const left = this.left.subarray(0, this.loop);
    const right = this.right.subarray(0, this.loop);
    let top = 0;
    for (let i = 0; i < this.loop; i++) top = Math.max(top, Math.abs(left[i]), Math.abs(right[i]));
    for (let i = 0; i < this.loop; i++) {
      left[i] *= peak / top;
      right[i] *= peak / top;
    }
    return { left, right, sr: this.sr, loudness: this.loudness, seconds: this.loop / this.sr };
  }
}

// Home and lobby: slow swing, a vibraphone over an electric piano. 16 bars in C.
function lounge() {
  const song = new Song(96, 64);
  const sr = song.sr;
  const SWING = 2 / 3; // where the off-beat falls within a beat

  const DM9 = ['F3', 'A3', 'C4', 'E4'];
  const G13 = ['F3', 'A3', 'B3', 'E4'];
  const CMAJ9 = ['E3', 'G3', 'B3', 'D4'];
  const AM9 = ['G3', 'B3', 'C4', 'E4'];
  const GM9 = ['F3', 'A3', 'A#3', 'D4'];
  const C13 = ['E3', 'A3', 'A#3', 'D4'];
  const FMAJ9 = ['E3', 'G3', 'A3', 'C4'];
  const FM6 = ['F3', 'G#3', 'C4', 'D4'];
  const EM7 = ['G3', 'B3', 'D4', 'E4'];
  const A7B9 = ['G3', 'A#3', 'C#4', 'E4'];
  const C69 = ['E3', 'A3', 'D4', 'G4'];

  // Per bar: the chords (one, or two sharing the bar), four bass notes, and the tune as
  // [beat in the bar, note, length in beats].
  const bars = [
    { chords: [DM9], bass: ['D2', 'F2', 'A2', 'G#2'], tune: [[SWING, 'A4', 0.33], [1, 'C5', 1], [2, 'E5', 1.5], [3 + SWING, 'D5', 0.33]] },
    { chords: [G13], bass: ['G2', 'B2', 'D3', 'C#3'], tune: [[0, 'B4', 2], [2, 'A4', 0.67], [2 + SWING, 'G4', 0.33], [3, 'E4', 1]] },
    { chords: [CMAJ9], bass: ['C3', 'G2', 'E2', 'A#2'], tune: [[0, 'G4', 2.5], [3 + SWING, 'E4', 0.33]] },
    { chords: [AM9], bass: ['A2', 'C3', 'E3', 'D#3'], tune: [[0, 'C5', 1], [1, 'B4', 1], [2, 'G4', 2]] },
    { chords: [DM9], bass: ['D3', 'C3', 'A2', 'G#2'], tune: [[SWING, 'F4', 0.33], [1, 'A4', 0.67], [1 + SWING, 'C5', 0.33], [2, 'E5', 1], [3, 'F5', 1]] },
    { chords: [G13], bass: ['G2', 'F2', 'E2', 'D2'], tune: [[0, 'E5', 1.67], [1 + SWING, 'D5', 0.33], [2, 'B4', 1], [3, 'A4', 1]] },
    { chords: [CMAJ9], bass: ['C2', 'E2', 'G2', 'A2'], tune: [[0, 'G4', 3]] },
    { chords: [GM9, C13], bass: ['G2', 'A#2', 'C3', 'E2'], tune: [[0, 'A#4', 1], [1, 'D5', 1], [2, 'E5', 1], [3, 'G5', 1]] },
    { chords: [FMAJ9], bass: ['F2', 'A2', 'C3', 'A2'], tune: [[0, 'A5', 2], [2, 'G5', 0.67], [2 + SWING, 'E5', 0.33], [3, 'C5', 1]] },
    { chords: [FM6], bass: ['F2', 'G#2', 'C3', 'F2'], tune: [[0, 'G#5', 2], [2, 'G5', 0.67], [2 + SWING, 'F5', 0.33], [3, 'D5', 1]] },
    { chords: [EM7], bass: ['E2', 'G2', 'B2', 'A#2'], tune: [[0, 'G5', 1.67], [1 + SWING, 'E5', 0.33], [2, 'D5', 1], [3, 'B4', 1]] },
    { chords: [A7B9], bass: ['A2', 'C#3', 'E3', 'D#3'], tune: [[0, 'C#5', 2], [2, 'E5', 1], [3, 'G5', 1]] },
    { chords: [DM9], bass: ['D3', 'A2', 'F2', 'G#2'], tune: [[0, 'F5', 1.67], [1 + SWING, 'E5', 0.33], [2, 'D5', 1], [3, 'A4', 1]] },
    { chords: [G13], bass: ['G2', 'B2', 'D3', 'C#3'], tune: [[0, 'B4', 1], [1, 'D5', 1], [2, 'F5', 1], [3, 'E5', 1]] },
    { chords: [C69], bass: ['C3', 'G2', 'A2', 'F2'], tune: [[0, 'E5', 0.67], [SWING, 'D5', 0.33], [1, 'C5', 2.5]] },
    { chords: [EM7, A7B9], bass: ['E2', 'G2', 'A2', 'C#2'], tune: [] },
  ];

  bars.forEach((bar, index) => {
    const start = index * 4;

    // Piano: on the first beat and just before the third; some bars answer off the beat instead
    const hits = bar.chords.length === 2
      ? [[0, 1.6, bar.chords[0]], [2, 1.6, bar.chords[1]]]
      : index % 4 === 2
        ? [[SWING, 1.0, bar.chords[0]], [2 + SWING, 1.2, bar.chords[0]]]
        : [[0, 1.3, bar.chords[0]], [1 + SWING, 2.0, bar.chords[0]]];
    for (const [beat, length, chord] of hits) {
      const force = song.touch();
      chord.forEach((name, string) => {
        const seconds = length * song.beatSeconds;
        const samples = song.note(`ep/${name}/${length}`, () => epiano(hz(name), seconds, sr, 0.9));
        song.add('piano', samples, start + beat + string * 0.012, 0.12 * force, 0.3, 0.25);
      });
    }

    bar.bass.forEach((name, beat) => {
      const samples = song.note(`bass/${name}`, () => bass(hz(name), 0.95 * song.beatSeconds, sr));
      song.add('bass', samples, start + beat, 0.4 * song.touch(0.08), 0, 0.03);
    });

    for (const [beat, name, length] of bar.tune) {
      const samples = song.note(`vibes/${name}/${length}`, () => vibes(hz(name), length * song.beatSeconds, sr));
      song.add('tune', samples, start + beat, 0.2 * song.touch(0.1), -0.15, 0.35);
    }

    // Drums: the ride cymbal's "ding, ding-a-ding", a foot on two and four, a light bass drum
    for (const [beat, loud] of [[0, 0.8], [1, 1], [1 + SWING, 0.6], [2, 0.8], [3, 1], [3 + SWING, 0.6]]) {
      song.add('drums', song.note('ride', () => drums.ride(sr, song.rng)), start + beat, 0.1 * loud * song.touch(), 0.35, 0.2);
    }
    for (const beat of [1, 3]) {
      song.add('drums', song.note('foot', () => drums.foot(sr, song.rng)), start + beat, 0.1, -0.2, 0.1);
    }
    song.add('drums', song.note('kick', () => drums.kick(sr)), start, 0.3, 0, 0.02);
    if (index % 2 === 1) {
      song.add('drums', song.note('rim', () => drums.rim(sr, song.rng)), start + 3, 0.16, -0.35, 0.3);
    }
  });
  return song.finish();
}

// The table: a bossa nova, a nylon guitar and a flute. 32 bars in A minor.
function bossa() {
  const song = new Song(120, 128);
  const sr = song.sr;

  const chords = {
    Am7: { guitar: ['A3', 'C4', 'E4', 'G4'], root: 'A2', fifth: 'E2' },
    Dm7: { guitar: ['A3', 'C4', 'F4'], root: 'D3', fifth: 'A2' },
    G7: { guitar: ['F3', 'B3', 'D4'], root: 'G2', fifth: 'D3' },
    Cmaj7: { guitar: ['G3', 'B3', 'E4'], root: 'C3', fifth: 'G2' },
    Fmaj7: { guitar: ['A3', 'C4', 'E4'], root: 'F2', fifth: 'C3' },
    Bm7b5: { guitar: ['A3', 'D4', 'F4'], root: 'B2', fifth: 'F2' },
    E7: { guitar: ['G#3', 'D4', 'E4'], root: 'E2', fifth: 'B2' },
    Em7: { guitar: ['G3', 'B3', 'D4'], root: 'E2', fifth: 'B2' },
  };
  const ROUND = ['Am7', 'Dm7', 'G7', 'Cmaj7', 'Fmaj7', 'Bm7b5', 'E7', 'Am7'];
  const BRIDGE = ['Fmaj7', 'G7', 'Em7', 'Am7', 'Dm7', 'G7', 'Cmaj7', 'E7'];
  const harmony = [...ROUND, ...ROUND, ...BRIDGE, ...ROUND];

  // The tunes, bar by bar, as [beat in the bar, note, length in beats]
  const FIRST = [
    [[0, 'E5', 1.5], [1.5, 'D5', 0.5], [2, 'C5', 1], [3, 'A4', 1]],
    [[0, 'F5', 1.5], [1.5, 'E5', 0.5], [2, 'D5', 2]],
    [[0, 'D5', 1.5], [1.5, 'C5', 0.5], [2, 'B4', 1], [3, 'G4', 1]],
    [[0, 'E5', 1.5], [1.5, 'D5', 0.5], [2, 'C5', 2]],
    [[0, 'C5', 1.5], [1.5, 'B4', 0.5], [2, 'A4', 1], [3, 'F4', 1]],
    [[0, 'D5', 1.5], [1.5, 'C5', 0.5], [2, 'B4', 2]],
    [[0, 'G#4', 1], [1, 'B4', 1], [2, 'D5', 1], [3, 'E5', 1]],
    [[0, 'C5', 3]],
  ];
  const SECOND = [
    [[0, 'A5', 1.5], [1.5, 'G5', 0.5], [2, 'E5', 1], [3, 'C5', 1]],
    [[0, 'D5', 0.5], [0.5, 'F5', 0.5], [1, 'A5', 1.5], [2.5, 'G5', 0.5], [3, 'F5', 1]],
    [[0, 'G5', 1.5], [1.5, 'F5', 0.5], [2, 'D5', 1], [3, 'B4', 1]],
    [[0, 'C5', 0.5], [0.5, 'E5', 0.5], [1, 'G5', 2], [3, 'E5', 1]],
    [[0, 'F5', 1.5], [1.5, 'E5', 0.5], [2, 'C5', 1], [3, 'A4', 1]],
    [[0, 'B4', 0.5], [0.5, 'D5', 0.5], [1, 'F5', 1.5], [2.5, 'D5', 0.5], [3, 'B4', 1]],
    [[0, 'E5', 1.5], [1.5, 'D5', 0.5], [2, 'B4', 1], [3, 'G#4', 1]],
    [[0, 'A4', 3]],
  ];
  const BRIDGE_TUNE = [
    [[0, 'A5', 3], [3, 'G5', 1]],
    [[0, 'F5', 2], [2, 'D5', 1], [3, 'B4', 1]],
    [[0, 'G5', 3], [3, 'E5', 1]],
    [[0, 'E5', 2], [2, 'C5', 2]],
    [[0, 'F5', 3], [3, 'E5', 1]],
    [[0, 'D5', 2], [2, 'B4', 1], [3, 'G4', 1]],
    [[0, 'E5', 4]],
    [[0, 'D5', 1], [1, 'B4', 1], [2, 'G#4', 2]],
  ];

  harmony.forEach((name, index) => {
    const start = index * 4;
    const chord = chords[name];
    const section = Math.floor(index / 8); // 0 and 1: the round, 2: the bridge, 3: the round again
    const within = index % 8;

    // Guitar: the bossa pattern runs over two bars, in eighth notes
    const strums = index % 2 === 0 ? [0, 1.5, 3] : [0.5, 2, 3];
    for (const beat of strums) {
      const force = song.touch();
      chord.guitar.forEach((note, string) => {
        const samples = song.note(`guitar/${note}`, () => pluck(hz(note), 1.1, song.rng, sr));
        song.add('guitar', samples, start + beat + string * 0.02, 0.34 * force, -0.3, 0.2);
      });
    }

    // Bass: root, fifth, root, fifth, the fifths arriving an eighth early
    for (const [beat, note, length] of [[0, chord.root, 1.4], [1.5, chord.fifth, 0.45], [2, chord.root, 1.4], [3.5, chord.fifth, 0.45]]) {
      const samples = song.note(`bass/${note}/${length}`, () => bass(hz(note), length * song.beatSeconds, sr));
      song.add('bass', samples, start + beat, 0.42 * song.touch(0.08), 0, 0.03);
    }

    // The flute carries the round; in the bridge the electric piano answers over strings
    const tune = [FIRST, SECOND, BRIDGE_TUNE, SECOND][section][within];
    for (const [beat, note, length] of tune) {
      const seconds = length * song.beatSeconds;
      if (section === 2) {
        const samples = song.note(`ep/${note}/${length}`, () => epiano(hz(note), seconds, sr, 1));
        song.add('tune', samples, start + beat, 0.2 * song.touch(0.1), 0.25, 0.35);
      } else {
        const samples = song.note(`flute/${note}/${length}`, () => flute(hz(note), seconds * 0.96, song.rng, sr));
        song.add('tune', samples, start + beat, 0.15 * song.touch(0.08), 0.1, 0.4);
      }
    }
    if (section >= 2) {
      for (const note of chord.guitar) {
        const samples = song.note(`strings/${note}`, () => strings(hz(note) * 2, 4 * song.beatSeconds, sr));
        song.add('strings', samples, start, 0.05, 0.2, 0.5);
      }
    }

    // Percussion: a shaker on every eighth, the bossa rim pattern, a soft bass drum
    for (let eighth = 0; eighth < 8; eighth++) {
      const loud = eighth % 2 === 1 ? 1 : 0.55;
      song.add('drums', song.note('shaker', () => drums.shaker(sr, song.rng)), start + eighth * 0.5, 0.09 * loud * song.touch(), 0.45, 0.1);
    }
    for (const beat of index % 2 === 0 ? [0, 1.5, 3] : [1, 2.5]) {
      song.add('drums', song.note('rim', () => drums.rim(sr, song.rng)), start + beat, 0.15, -0.45, 0.3);
    }
    for (const [beat, loud] of [[0, 1], [1.5, 0.6], [2, 1], [3.5, 0.6]]) {
      song.add('drums', song.note('kick', () => drums.kick(sr)), start + beat, 0.3 * loud, 0, 0.02);
    }
    for (const beat of [1, 3]) {
      song.add('drums', song.note('hat', () => drums.hat(sr, song.rng)), start + beat, 0.07, 0.3, 0.1);
    }
  });
  return song.finish();
}

const music = { music_menu: lounge, music_table: bossa };

// ---------- files ----------

// Cuts the silence off the end, fades the last few milliseconds, and sets the loudest point.
function tidy(samples, peak = 0.85) {
  let top = 0;
  for (const s of samples) top = Math.max(top, Math.abs(s));
  let end = samples.length;
  while (end > 1 && Math.abs(samples[end - 1]) < top * 0.002) end--;
  const out = samples.slice(0, Math.min(samples.length, end + Math.round(0.005 * SR)));
  const fade = Math.min(out.length, Math.round(0.004 * SR));
  for (let i = 0; i < out.length; i++) {
    out[i] *= peak / top;
    if (i >= out.length - fade) out[i] *= (out.length - 1 - i) / fade;
  }
  return out;
}

// 16-bit PCM; `channels` is one array for mono, two for stereo.
function writeWav(file, channels, sr) {
  const frames = channels[0].length;
  const bytes = frames * channels.length * 2;
  const buffer = Buffer.alloc(44 + bytes);
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + bytes, 4);
  buffer.write('WAVEfmt ', 8);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(channels.length, 22);
  buffer.writeUInt32LE(sr, 24);
  buffer.writeUInt32LE(sr * channels.length * 2, 28);
  buffer.writeUInt16LE(channels.length * 2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(bytes, 40);
  let at = 44;
  for (let i = 0; i < frames; i++) {
    for (const channel of channels) {
      buffer.writeInt16LE(Math.round(Math.max(-1, Math.min(1, channel[i])) * 32767), at);
      at += 2;
    }
  }
  fs.writeFileSync(file, buffer);
}

function decibels(channels) {
  let sum = 0;
  let count = 0;
  for (const channel of channels) {
    for (const s of channel) sum += s * s;
    count += channel.length;
  }
  return (10 * Math.log10(sum / count)).toFixed(1);
}

function main() {
  const wanted = process.argv.slice(2).filter((arg) => !arg.startsWith('--'));
  const report = process.argv.includes('--report');
  const unknown = wanted.filter((name) => !sounds[name] && !music[name]);
  if (unknown.length > 0) {
    console.error(`No such sound: ${unknown.join(', ')}`);
    process.exit(1);
  }
  fs.mkdirSync(OUT, { recursive: true });
  const chosen = (name) => wanted.length === 0 || wanted.includes(name);

  for (const name of Object.keys(sounds).filter(chosen)) {
    const samples = tidy(sounds[name]());
    writeWav(path.join(OUT, `${name}.wav`), [samples], SR);
    if (report) console.log(`${name.padEnd(12)} ${(samples.length / SR).toFixed(2)}s  ${decibels([samples])} dB`);
  }
  for (const name of Object.keys(music).filter(chosen)) {
    const song = music[name]();
    writeWav(path.join(OUT, `${name}.wav`), [song.left, song.right], song.sr);
    if (report) {
      console.log(`${name.padEnd(12)} ${song.seconds.toFixed(2)}s  ${decibels([song.left, song.right])} dB`);
      const whole = Object.values(song.loudness).reduce((a, b) => a + b, 0);
      for (const [part, energy] of Object.entries(song.loudness)) {
        console.log(`    ${part.padEnd(8)} ${(10 * Math.log10(energy / whole)).toFixed(1)} dB of the mix`);
      }
    }
  }
  console.log(`Wrote ${fs.readdirSync(OUT).filter((file) => file.endsWith('.wav')).length} sounds to ${OUT}`);
}

if (require.main === module) main();
else module.exports = { hz, sounds, music, instruments: { chime, marimba, brass, epiano, vibes, bass, pluck, flute, strings }, rngFrom, SR, MUSIC_SR };
