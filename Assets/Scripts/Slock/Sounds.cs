using UnityEngine;

namespace Slock
{
    /// <summary>
    /// Sound effects (2D, not positional). Clips live in Resources/Slock/Sounds and are made by art-work/sounds.py;
    /// how loud each plays is set here.
    /// </summary>
    public static class Sounds
    {
        const float PelletVolume = 0.2f;    // kept quiet: pellets go off constantly and mustn't become a distraction
        const float PelletDetune = 0.15f;   // semitones of random pitch wobble, so repeats never sound copy-pasted
        const int Voices = 6;               // pops can overlap; each gets its own source so detuning doesn't bleed

        static AudioClip[] pellets;
        static AudioSource[] voices;
        static int nextVoice, lastPellet = -1;

        public static void Init(GameObject host)
        {
            pellets = new AudioClip[6];
            for (int i = 0; i < pellets.Length; i++) pellets[i] = Resources.Load<AudioClip>($"Slock/Sounds/Pellet{i + 1}");
            voices = new AudioSource[Voices];
            for (int i = 0; i < Voices; i++)
            {
                var s = host.AddComponent<AudioSource>();
                s.playOnAwake = false;
                s.spatialBlend = 0f;
                voices[i] = s;
            }
        }

        /// <summary>A pellet eaten: one of the six pops at random, never the same one twice in a row.</summary>
        public static void Pellet()
        {
            if (voices == null) return;
            int i = Random.Range(0, pellets.Length - 1);
            if (i >= lastPellet && lastPellet >= 0) i++;
            lastPellet = i;
            Play(pellets[i], PelletVolume * Random.Range(0.8f, 1f), Mathf.Pow(2f, Random.Range(-PelletDetune, PelletDetune) / 12f));
        }

        static void Play(AudioClip clip, float volume, float pitch)
        {
            if (clip == null) return;
            var s = voices[nextVoice];
            nextVoice = (nextVoice + 1) % voices.Length;
            s.clip = clip;
            s.volume = volume;
            s.pitch = pitch;
            s.Play();
        }
    }
}
