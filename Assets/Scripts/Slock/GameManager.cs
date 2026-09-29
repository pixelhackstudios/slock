using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

namespace Slock
{
    /// <summary>
    /// Owns a run: builds the scene, streams maze chunks around the slock, tracks score/time/height and
    /// draws the HUD + leaderboard (IMGUI for now; swap to UI Toolkit once the design settles).
    /// </summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager I { get; private set; }

        enum State { Title, Playing, Paused, GameOver }

        const float StartTime = 35f;
        const float PickupTime = 5f;
        const float PowerDuration = 7f;
        const float PelletTime = 1f;
        const float WormTime = 10f;
        const int PelletPoints = 10, GoldPelletPoints = 30;
        const float ClockTime = 20f;
        const float WormRespawn = 8f;
        const int ChunksAhead = 2, ChunksBehind = 1;
        const float FallDistance = 5f;

        State state;
        SlockController slock;
        TiltCameraRig rig;
        Transform worldRoot;
        readonly Dictionary<int, MazeChunk> chunks = new();

        int seed;
        float timeLeft, runSeconds, maxZ, flash;
        int bonusScore, height, pickups, pelletsEaten, wormsEaten, wormChain, pelletsHere;
        float powerUntil;

        public bool PowerActive => state == State.Playing && Time.time < powerUntil;
        public float PowerRemaining => Mathf.Max(0f, powerUntil - Time.time);
        string endReason = "";

        // Game-over / leaderboard entry
        string playerName = "";
        bool canSubmit;
        int submittedRank;

        readonly List<(string text, float until, Color color)> popups = new();

        int Score => Mathf.Max(0, Mathf.FloorToInt(maxZ * 10f)) + bonusScore;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (FindAnyObjectByType<GameManager>() == null)
                new GameObject("Slock Game").AddComponent<GameManager>();
        }

        void Awake()
        {
            I = this;
            Visuals.Init();
            ControlSettings.Load();
            playerName = PlayerPrefs.GetString("slock.lastName", "");

            SetupCameraAndLights();
            worldRoot = new GameObject("World").transform;
            slock = SlockController.Create();
            rig.target = slock.transform;

            NewWorld();
            state = State.Title;

            if (System.Array.IndexOf(System.Environment.GetCommandLineArgs(), "-slockdiag") >= 0)
                StartCoroutine(Diagnose());
            PhotoMode.StartIfRequested(this);
        }

        /// <summary>
        /// Build troubleshooting: run the player with -slockdiag to log every material's shader status,
        /// start a run, save a screenshot next to the log, and quit.
        /// </summary>
        System.Collections.IEnumerator Diagnose()
        {
            foreach (var f in typeof(Visuals).GetFields())
                if (f.GetValue(null) is Material m)
                    Debug.Log($"[slockdiag] {f.Name}: shader={m.shader.name} supported={m.shader.isSupported} " +
                              $"queue={m.renderQueue} keywords={string.Join(",", m.shaderKeywords)}");
            StartRun();
            yield return new WaitForSeconds(3f);
            var path = System.IO.Path.Combine(Application.persistentDataPath, "slockdiag.png");
            ScreenCapture.CaptureScreenshot(path);
            Debug.Log("[slockdiag] screenshot " + path);
            yield return new WaitForSeconds(1f);
            Application.Quit();
        }

        void SetupCameraAndLights()
        {
            var cam = Camera.main;
            if (cam == null)
            {
                cam = new GameObject("Main Camera") { tag = "MainCamera" }.AddComponent<Camera>();
                cam.gameObject.AddComponent<AudioListener>();
            }
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = Color.black;
            cam.fieldOfView = 40f;
            cam.nearClipPlane = 0.3f;
            cam.farClipPlane = 250f;
            if (!cam.TryGetComponent(out rig)) rig = cam.gameObject.AddComponent<TiltCameraRig>();

            var sun = RenderSettings.sun;
            if (sun == null) sun = GameObject.Find("Directional Light")?.GetComponent<Light>();
            if (sun == null) sun = new GameObject("Sun").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.transform.rotation = Quaternion.Euler(58f, -35f, 0f);
            sun.intensity = 1.3f;
            sun.color = Color.white;                       // neutral, so tile art shows its true colours
            sun.useColorTemperature = false;               // the template's sun is set to a warm colour temperature
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.75f;

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.36f, 0.36f, 0.36f); // neutral grey fill
            // The scene's baked environment (the template's blue-sky/brown-ground sky) otherwise still tints
            // everything: replace its ambient probe and reflections with plain neutral grey.
            var ambient = new UnityEngine.Rendering.SphericalHarmonicsL2();
            ambient.AddAmbientLight(RenderSettings.ambientLight);
            RenderSettings.ambientProbe = ambient;
            RenderSettings.defaultReflectionMode = UnityEngine.Rendering.DefaultReflectionMode.Custom;
            RenderSettings.customReflectionTexture = NeutralCubemap(new Color(0.3f, 0.3f, 0.3f));
            RenderSettings.skybox = null;
            RenderSettings.fog = false;
        }

        static Cubemap NeutralCubemap(Color c)
        {
            var cube = new Cubemap(8, TextureFormat.RGBA32, false);
            var px = new Color[8 * 8];
            for (int i = 0; i < px.Length; i++) px[i] = c;
            foreach (CubemapFace f in System.Enum.GetValues(typeof(CubemapFace)))
                if (f != CubemapFace.Unknown) cube.SetPixels(px, f);
            cube.Apply();
            return cube;
        }

        // ------------------------------------------------------------------ run lifecycle

        void NewWorld()
        {
            foreach (var c in chunks.Values) Destroy(c.gameObject);
            chunks.Clear();
            seed = Random.Range(1, int.MaxValue / 8);
            StreamChunks(0);

            slock.SetSizeImmediate(MazeChunk.TileSizeOf(0));
            slock.SetGrid(MazeChunk.TileSizeOf(0), MazeChunk.StartZOf(0));
            slock.ResetTo(new Vector3(0f, slock.Height * 0.5f + 0.02f, MazeChunk.StartZOf(0) + MazeChunk.TileSizeOf(0)));
            rig.zoom = 1f;
            rig.SnapToTarget();
            timeLeft = StartTime;
            runSeconds = maxZ = 0f;
            bonusScore = height = pickups = pelletsEaten = wormsEaten = wormChain = pelletsHere = 0;
            powerUntil = 0f;
            popups.Clear();
        }

        /// <summary>Start a run without a click (automated playtests).</summary>
        public void BeginRun() => StartRun();

        /// <summary>Photo mode: make sure sections around <paramref name="current"/> exist before teleporting there.</summary>
        public void EnsureSections(int current) => StreamChunks(current);

        /// <summary>Photo mode: switch on power mode (blue worms) for a while.</summary>
        public void ForcePower(float seconds) => powerUntil = Time.time + seconds;

        void StartRun()
        {
            NewWorld();
            state = State.Playing;
            rig.inputEnabled = true;
            rig.ResetStick();
            CaptureMouse(true);
            Time.timeScale = 1f;
            Popup("GO!", Color.white, 1f);
        }

        void EndRun(string reason)
        {
            state = State.GameOver;
            endReason = reason;
            rig.inputEnabled = false;
            CaptureMouse(false);
            canSubmit = Leaderboard.Qualifies(Score);
            submittedRank = 0;
        }

        void SetPaused(bool paused)
        {
            state = paused ? State.Paused : State.Playing;
            Time.timeScale = paused ? 0f : 1f;
            rig.inputEnabled = !paused;
            CaptureMouse(!paused);
        }

        /// <summary>While playing, trackball mode hides and locks the cursor; absolute mode keeps it in the window.</summary>
        static void CaptureMouse(bool playing)
        {
            Cursor.lockState = !playing ? CursorLockMode.None
                : ControlSettings.Trackball ? CursorLockMode.Locked : CursorLockMode.Confined;
            Cursor.visible = !(playing && ControlSettings.Trackball);
        }

        void StreamChunks(int current)
        {
            for (int i = Mathf.Max(0, current - ChunksBehind); i <= current + ChunksAhead; i++)
                if (!chunks.ContainsKey(i))
                    chunks[i] = MazeChunk.Create(i, seed, worldRoot);

            var stale = new List<int>();
            foreach (var k in chunks.Keys)
                if (k < current - ChunksBehind - 1) stale.Add(k);
            foreach (var k in stale) { Destroy(chunks[k].gameObject); chunks.Remove(k); }
        }

        // ------------------------------------------------------------------ frame

        void Update()
        {
            var kb = Keyboard.current;
            var mouse = Mouse.current;
            bool click = mouse != null && mouse.leftButton.wasPressedThisFrame;
            bool esc = kb != null && kb.escapeKey.wasPressedThisFrame;

            switch (state)
            {
                case State.Title:
                    if (kb != null && kb.qKey.wasPressedThisFrame) Quit();
                    else if (click || (kb != null && kb.spaceKey.wasPressedThisFrame)) StartRun();
                    break;

                case State.Playing:
                    if (esc) { SetPaused(true); break; }
                    if (kb != null && kb.rKey.wasPressedThisFrame) { StartRun(); break; }
                    TickRun();
                    break;

                case State.Paused:
                    if (kb != null && kb.qKey.wasPressedThisFrame) Quit();
                    else if (kb != null && kb.rKey.wasPressedThisFrame) StartRun();
                    else if (esc) SetPaused(false);   // clicks belong to the controls panel
                    break;

                // GameOver input (name entry / Enter) is handled in OnGUI alongside the text field.
            }

            flash = Mathf.Max(0f, flash - Time.unscaledDeltaTime * 2f);
        }

        static void Quit()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
#else
            Application.Quit();
#endif
        }

        void TickRun()
        {
            float dt = Time.deltaTime;
            timeLeft -= dt;
            runSeconds += dt;

            var p = slock.transform.position;
            maxZ = Mathf.Max(maxZ, p.z);
            int current = Mathf.Max(0, MazeChunk.IndexAt(p.z));
            StreamChunks(current);
            if (chunks.TryGetValue(current, out var here)) slock.SetGrid(here.TileSize, here.Z0);
            EatPellets(p, current);

            float floor = MazeChunk.FloorYOf(current);
            if (p.y < floor - FallDistance) { EndRun("You slid off the edge"); return; }
            if (timeLeft <= 0f) { timeLeft = 0f; EndRun("Out of time"); }
        }

        void EatPellets(Vector3 p, int current)
        {
            if (!chunks.TryGetValue(current, out var chunk)) return;
            if (chunk.TryEatPellet(p, out bool gold))
            {
                pelletsEaten++;
                bonusScore += gold ? GoldPelletPoints : PelletPoints;
                timeLeft += PelletTime;
                if (chunk.PelletsLeft == 0 && !chunk.GateOpen)
                {
                    chunk.OpenGate();
                    Popup("GATE OPEN!", new Color(0.3f, 1f, 0.95f), 1.5f);
                }
            }
            pelletsHere = chunk.PelletsLeft;
        }

        // ------------------------------------------------------------------ events from the world

        public void OnPickup(Pickup pickup)
        {
            if (state != State.Playing) return;
            switch (pickup.kind)
            {
                case Pickup.Kind.Clock:
                    timeLeft += ClockTime;
                    bonusScore += 250;
                    Popup($"+{ClockTime:0}s!", new Color(0.4f, 0.9f, 1f), 1.4f);
                    return;
                case Pickup.Kind.Key:
                    var owner = pickup.GetComponentInParent<MazeChunk>();
                    if (owner != null && !owner.GateOpen) owner.OpenGate();
                    bonusScore += 500;
                    Popup("KEY!  GATE OPEN", new Color(1f, 0.4f, 1f), 1.6f);
                    return;
            }
            int value = 100 + height * 10;
            bonusScore += value;
            pickups++;
            timeLeft += PickupTime;
            powerUntil = Time.time + PowerDuration;
            wormChain = 0;
            Popup($"POWER!   +{PickupTime:0}s", new Color(1f, 0.85f, 0.2f), 1.2f);
        }

        public void OnCheckpoint(int chunkIndex)
        {
            if (state != State.Playing) return;
            var d = Difficulty.For(chunkIndex);
            height = Mathf.Max(height, chunkIndex + 1);
            bonusScore += 250 * (chunkIndex + 1);
            timeLeft += d.TimeBonus;
            // Resolution up: the next section's blocks are smaller, and so is the slock.
            int block = MazeChunk.BlockOf(chunkIndex + 1);
            float size = MazeChunk.TileSizeOf(chunkIndex + 1);
            slock.ShrinkTo(Mathf.Min(slock.Size, size));
            rig.zoom = Mathf.Lerp(1f, size, 0.5f);
            Popup($"FLOOR {height}   +{d.TimeBonus:0}s", new Color(0.3f, 1f, 0.95f), 1.6f);
            if (block < MazeChunk.BlockOf(chunkIndex)) Popup($"BLOCK {block}", Color.white, 1.6f);
        }

        readonly Dictionary<Worm, float> wormCooldown = new();

        public void OnWormHit(Worm worm, SlockController s)
        {
            if (state != State.Playing || worm.Eaten) return;
            if (PowerActive)
            {
                int pts = 200 << Mathf.Min(wormChain, 3); // 200, 400, 800, 1600
                wormChain++;
                wormsEaten++;
                bonusScore += pts;
                timeLeft += WormTime;
                float refund = worm.stolenTime;
                worm.stolenTime = 0f;
                if (refund > 0.05f) timeLeft += refund;
                worm.GetEaten(WormRespawn);
                string back = refund > 0.05f ? $"   +{refund:0}s back" : "";
                Popup($"CHOMP! +{pts}   +{WormTime:0}s{back}", new Color(0.4f, 0.6f, 1f), 1.2f);
                return;
            }
            if (wormCooldown.TryGetValue(worm, out var until) && Time.time < until) return;
            wormCooldown[worm] = Time.time + 1f;
            s.BounceBack(worm.transform.position, 3f);
            float stolen = timeLeft / 3f;
            timeLeft -= stolen;
            worm.stolenTime += stolen;
            flash = 1f;
            Popup($"-{stolen:0}s", new Color(0.5f, 1f, 0.2f), 1f);
        }

        void Popup(string text, Color color, float seconds) =>
            popups.Add((text, Time.unscaledTime + seconds, color));

        void Submit()
        {
            playerName = string.IsNullOrWhiteSpace(playerName) ? "SLOCK" : playerName.Trim().ToUpperInvariant();
            PlayerPrefs.SetString("slock.lastName", playerName);
            submittedRank = Leaderboard.Submit(new LeaderboardEntry
            {
                name = playerName,
                score = Score,
                height = height,
                seconds = runSeconds,
                date = System.DateTime.Now.ToString("yyyy-MM-dd"),
            });
        }

        // ------------------------------------------------------------------ HUD (IMGUI)

        GUIStyle label, big, title, small;
        static readonly Color Red = new(1f, 0.25f, 0.33f), Cyan = new(0.35f, 0.75f, 1f);

        void Styles()
        {
            if (label != null) return;
            label = new GUIStyle(GUI.skin.label) { fontSize = 18, fontStyle = FontStyle.Bold, alignment = TextAnchor.UpperLeft };
            big = new GUIStyle(label) { fontSize = 52 };
            title = new GUIStyle(label) { fontSize = 96, alignment = TextAnchor.MiddleCenter };
            small = new GUIStyle(label) { fontSize = 16, fontStyle = FontStyle.Normal };
        }

        void Text(Rect r, string s, GUIStyle st, Color c, TextAnchor a)
        {
            var style = new GUIStyle(st) { alignment = a };
            style.normal.textColor = new Color(0, 0, 0, c.a * 0.6f);
            GUI.Label(new Rect(r.x + 2, r.y + 2, r.width, r.height), s, style);
            style.normal.textColor = c;
            GUI.Label(r, s, style);
        }

        void OnGUI()
        {
            Styles();
            float w = Screen.width, h = Screen.height;

            if (flash > 0f)
            {
                GUI.color = new Color(0.4f, 1f, 0.2f, flash * 0.25f);
                GUI.DrawTexture(new Rect(0, 0, w, h), Texture2D.whiteTexture);
                GUI.color = Color.white;
            }

            if (state is State.Playing or State.Paused or State.GameOver)
            {
                Text(new Rect(40, 20, 400, 30), "RED · SCORE", label, Red, TextAnchor.UpperLeft);
                Text(new Rect(40, 44, 500, 70), Score.ToString("N0"), big, Red, TextAnchor.UpperLeft);
                Text(new Rect(w / 2 - 200, 20, 400, 30), "REMAINING TIME", label, Color.white, TextAnchor.UpperCenter);
                var tc = timeLeft < 10f && Mathf.Repeat(Time.unscaledTime, 0.5f) < 0.25f ? Red : Color.white;
                Text(new Rect(w / 2 - 200, 44, 400, 70), Mathf.CeilToInt(timeLeft).ToString(), big, tc, TextAnchor.UpperCenter);
                Text(new Rect(w - 440, 20, 400, 30), "HEIGHT", label, Cyan, TextAnchor.UpperRight);
                Text(new Rect(w - 440, 44, 400, 70), height.ToString(), big, Cyan, TextAnchor.UpperRight);
                Text(new Rect(w - 440, 140, 400, 30), $"BLOCK  {MazeChunk.BlockOf(height)}", label, new Color(1f, 1f, 1f, 0.7f), TextAnchor.UpperRight);
                Text(new Rect(w - 440, 112, 400, 30), pelletsHere > 0 ? $"PELLETS LEFT  {pelletsHere}" : "GATE OPEN", label,
                    new Color(1f, 0.92f, 0.7f), TextAnchor.UpperRight);
                if (PowerActive)
                    Text(new Rect(w / 2 - 200, 112, 400, 30), $"POWER  {PowerRemaining:0.0}", label, new Color(0.45f, 0.6f, 1f), TextAnchor.UpperCenter);

                DrawTiltGauge(new Vector2(80, h - 80), 55f);

                float y = h * 0.3f;
                popups.RemoveAll(p => Time.unscaledTime > p.until);
                foreach (var p in popups)
                {
                    float a = Mathf.Clamp01(p.until - Time.unscaledTime);
                    Text(new Rect(0, y, w, 60), p.text, big, new Color(p.color.r, p.color.g, p.color.b, a), TextAnchor.MiddleCenter);
                    y += 60;
                }
            }

            switch (state)
            {
                case State.Title:
                    Dim(0.45f);
                    Text(new Rect(0, h * 0.14f, w, 120), "SLOCK", title, Red, TextAnchor.MiddleCenter);
                    Text(new Rect(0, h * 0.14f - 40, w, 30), "A PIXELHACK STUDIOS PRODUCTION  ·  IN ASSOCIATION WITH SCOTT O'NANSKI", small, new Color(1f, 1f, 1f, 0.75f), TextAnchor.MiddleCenter);
                    Text(new Rect(0, h * 0.14f + 100, w, 30), "tilt the world with the mouse · climb forever", small, Color.white, TextAnchor.MiddleCenter);
                    DrawBoard(new Rect(w / 2 - 230, h * 0.36f, 460, 330));
                    Text(new Rect(0, h - 90, w, 30), "CLICK or SPACE to start   ·   Q to quit", label, Color.white, TextAnchor.MiddleCenter);
                    break;

                case State.Paused:
                    Dim(0.5f);
                    Text(new Rect(60, h * 0.4f, w * 0.4f, 80), "PAUSED", big, Color.white, TextAnchor.MiddleLeft);
                    Text(new Rect(60, h * 0.4f + 70, w * 0.45f, 30), "ESC to resume  ·  R to restart  ·  Q to quit", small, Color.white, TextAnchor.MiddleLeft);
                    Text(new Rect(60, h * 0.4f + 100, w * 0.45f, 60), "Tweak the controls on the right, then ESC to try them.", small, new Color(1, 1, 1, 0.7f), TextAnchor.UpperLeft);
                    DrawControlsPanel(new Rect(w - 600, 190, 560, Mathf.Min(h - 230, 840)));
                    break;

                case State.GameOver:
                    DrawGameOver(w, h);
                    break;
            }
        }

        void DrawGameOver(float w, float h)
        {
            Dim(0.6f);
            Text(new Rect(0, h * 0.1f, w, 80), endReason.ToUpperInvariant(), big, Red, TextAnchor.MiddleCenter);
            Text(new Rect(0, h * 0.1f + 70, w, 30),
                $"score {Score:N0}   ·   floor {height}   ·   {pelletsEaten} pellets   ·   {wormsEaten} slorms eaten   ·   {runSeconds:0}s", label, Color.white, TextAnchor.MiddleCenter);

            float y = h * 0.1f + 120;
            if (canSubmit && submittedRank == 0)
            {
                Text(new Rect(0, y, w, 30), "NEW HIGH SCORE — enter your name", label, Cyan, TextAnchor.MiddleCenter);
                GUI.SetNextControlName("name");
                var field = new GUIStyle(GUI.skin.textField) { fontSize = 26, alignment = TextAnchor.MiddleCenter };
                playerName = GUI.TextField(new Rect(w / 2 - 150, y + 36, 300, 44), playerName, 12, field);
                GUI.FocusControl("name");
                if (Event.current.type == EventType.KeyDown && Event.current.keyCode is KeyCode.Return or KeyCode.KeypadEnter)
                {
                    Submit();
                    Event.current.Use();
                }
                if (GUI.Button(new Rect(w / 2 - 70, y + 90, 140, 36), "Submit")) Submit();
                return;
            }

            if (submittedRank > 0)
                Text(new Rect(0, y, w, 30), $"You placed #{submittedRank}!", label, Cyan, TextAnchor.MiddleCenter);
            DrawBoard(new Rect(w / 2 - 230, y + 40, 460, 330), submittedRank);
            if (GUI.Button(new Rect(w / 2 - 90, y + 390, 180, 44), "Play again (Enter)")) StartRun();
            if (Event.current.type == EventType.KeyDown && Event.current.keyCode == KeyCode.Return && (submittedRank > 0 || !canSubmit))
            {
                Event.current.Use();
                StartRun();
            }
        }

        void DrawBoard(Rect r, int highlight = 0)
        {
            var list = Leaderboard.Load();
            Text(new Rect(r.x, r.y, r.width, 30), "LEADERBOARD", label, Cyan, TextAnchor.UpperCenter);
            if (list.Count == 0)
            {
                Text(new Rect(r.x, r.y + 40, r.width, 30), "no scores yet — be the first", small, Color.gray, TextAnchor.UpperCenter);
                return;
            }
            for (int i = 0; i < list.Count; i++)
            {
                var e = list[i];
                var c = i + 1 == highlight ? Red : Color.white;
                float y = r.y + 36 + i * 28;
                Text(new Rect(r.x, y, 40, 28), $"{i + 1}.", small, c, TextAnchor.UpperLeft);
                Text(new Rect(r.x + 40, y, 200, 28), e.name, small, c, TextAnchor.UpperLeft);
                Text(new Rect(r.x + 220, y, 80, 28), $"F{e.height}", small, c, TextAnchor.UpperRight);
                Text(new Rect(r.x + 300, y, 160, 28), e.score.ToString("N0"), small, c, TextAnchor.UpperRight);
            }
        }

        /// <summary>Tilt indicator: faint square = full tilt, crosshair = level, white ring = your input, red = the board.</summary>
        void DrawTiltGauge(Vector2 c, float radius)
        {
            GUI.color = new Color(1, 1, 1, 0.12f);
            GUI.DrawTexture(new Rect(c.x - radius, c.y - radius, radius * 2, radius * 2), Texture2D.whiteTexture);
            GUI.color = new Color(1, 1, 1, 0.35f);
            GUI.DrawTexture(new Rect(c.x - radius, c.y - 0.5f, radius * 2, 1), Texture2D.whiteTexture);
            GUI.DrawTexture(new Rect(c.x - 0.5f, c.y - radius, 1, radius * 2), Texture2D.whiteTexture);
            var s = rig.Stick;
            GUI.color = new Color(1, 1, 1, 0.8f);
            GUI.DrawTexture(new Rect(c.x + s.x * radius - 7, c.y - s.y * radius - 7, 14, 14), Texture2D.whiteTexture);
            GUI.color = Red;
            var t = rig.Tilt;
            GUI.DrawTexture(new Rect(c.x + t.x * radius - 5, c.y - t.y * radius - 5, 10, 10), Texture2D.whiteTexture);
            GUI.color = Color.white;
        }

        // ------------------------------------------------------------------ controls panel (pause screen)

        void DrawControlsPanel(Rect r)
        {
            GUI.color = new Color(0.02f, 0.02f, 0.04f, 0.93f);
            GUI.DrawTexture(r, Texture2D.whiteTexture);
            GUI.color = Color.white;
            float x = r.x + 20, w = r.width - 40, y = r.y + 14;
            Text(new Rect(x, y, w, 28), "CONTROLS", label, Cyan, TextAnchor.UpperLeft);
            y += 36;

            bool changed = false;
            var toggle = new GUIStyle(GUI.skin.toggle) { fontSize = 16 };
            toggle.normal.textColor = toggle.onNormal.textColor = Color.white;
            bool tb = GUI.Toggle(new Rect(x, y, w, 26), ControlSettings.Trackball,
                "  Trackball mode (mouse nudges the tilt, cursor hidden)", toggle);
            if (tb != ControlSettings.Trackball) { ControlSettings.Trackball = tb; changed = true; }
            y += 34;

            bool f16 = GUI.Toggle(new Rect(x, y, w, 26), ControlSettings.F16Response,
                "  F-16-inspired roll response", toggle);
            if (f16 != ControlSettings.F16Response) { ControlSettings.F16Response = f16; changed = true; }
            y += 34;

            changed |= Slider(ref y, x, w, "Mouse sensitivity", ref ControlSettings.Sensitivity, 0.2f, 3f, "tilt per mouse movement");
            if (!ControlSettings.F16Response)
                changed |= Slider(ref y, x, w, "Fine control", ref ControlSettings.ResponseCurve, 1f, 3f, "higher = gentler near level, same full tilt");
            if (ControlSettings.Trackball)
                changed |= Slider(ref y, x, w, "Auto-level", ref ControlSettings.Recenter, 0f, 3f, "board drifts back to level when you stop moving");
            changed |= Slider(ref y, x, w, "Tilt response time", ref ControlSettings.TiltSmoothing, 0f, 0.3f, "lower = board follows the mouse instantly");
            changed |= Slider(ref y, x, w, "World tilt (degrees)", ref ControlSettings.MaxTilt, 8f, 35f, "visible tilt and physical downhill use this same angle");
            changed |= Slider(ref y, x, w, "Gravity strength", ref ControlSettings.FallGravity, 5f, 80f, "magnitude of the tilted world gravity vector");
            changed |= Slider(ref y, x, w, "Surface friction", ref ControlSettings.Friction, 0f, 0.6f, "0 = ice; it only slides once the tilt's slope exceeds this");
            changed |= Slider(ref y, x, w, "Speed limit", ref ControlSettings.MaxSpeed, 10f, 60f, "safety cap only");

            if (changed) ControlSettings.Save();

            y += 6;
            if (GUI.Button(new Rect(x, y, 170, 32), "Reset to defaults")) ControlSettings.ResetDefaults();
            if (GUI.Button(new Rect(x + w - 150, y, 150, 32), "Resume (Esc)")) SetPaused(false);
        }

        GUIStyle sliderTrack, sliderThumb;

        /// <summary>Visible slider track + chunky cyan handle (the default skin's are nearly invisible on dark).</summary>
        void SliderStyles()
        {
            if (sliderTrack != null) return;
            sliderTrack = new GUIStyle(GUI.skin.horizontalSlider) { fixedHeight = 6, margin = new RectOffset(0, 0, 6, 6) };
            sliderTrack.normal.background = Solid(new Color(1f, 1f, 1f, 0.28f));
            sliderThumb = new GUIStyle(GUI.skin.horizontalSliderThumb) { fixedWidth = 18, fixedHeight = 18, margin = new RectOffset(0, 0, -6, 0) };
            sliderThumb.normal.background = sliderThumb.hover.background = sliderThumb.active.background = Solid(Cyan);
        }

        static Texture2D Solid(Color c)
        {
            var t = new Texture2D(1, 1);
            t.SetPixel(0, 0, c);
            t.Apply();
            return t;
        }

        bool Slider(ref float y, float x, float w, string name, ref float value, float min, float max, string hint)
        {
            Text(new Rect(x, y, w * 0.6f, 24), name, small, Color.white, TextAnchor.UpperLeft);
            Text(new Rect(x, y, w, 24), value.ToString(max <= 1f ? "0.00" : max <= 5f ? "0.0" : "0"), small, Cyan, TextAnchor.UpperRight);
            SliderStyles();
            float v = GUI.HorizontalSlider(new Rect(x, y + 24, w, 18), value, min, max, sliderTrack, sliderThumb);
            Text(new Rect(x, y + 38, w, 20), hint, small, new Color(1, 1, 1, 0.45f), TextAnchor.UpperLeft);
            y += 62;
            if (Mathf.Approximately(v, value)) return false;
            value = v;
            return true;
        }

        static void Dim(float a)
        {
            GUI.color = new Color(0, 0, 0, a);
            GUI.DrawTexture(new Rect(0, 0, Screen.width, Screen.height), Texture2D.whiteTexture);
            GUI.color = Color.white;
        }

        void OnDestroy()
        {
            Time.timeScale = 1f;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
            if (I == this) I = null;
        }
    }
}
