using UnityEngine;
using UnityEngine.InputSystem;

namespace Slock
{
    /// <summary>A stripped test where a real rigidbody moves only through gravity and contact with a tilted course.</summary>
    public class SlockPhysicsTruthTest : MonoBehaviour
    {
        public const string EditorSessionKey = "Slock.PhysicsTruthTest";

        const float BoardTiltLimit = 18f;
        const float MousePixelsForFullTilt = 480f;

        Rigidbody boardBody;
        Rigidbody slockBody;
        Camera testCamera;
        PhysicsMaterial contactMaterial;
        Vector2 boardInput;
        Vector3 originalGravity;
        float originalTimeScale;
        CursorLockMode originalCursorLock;
        bool originalCursorVisible;
        TiltCameraRig cameraRig;
        bool cameraRigWasEnabled;

        void Awake()
        {
            originalGravity = Physics.gravity;
            originalTimeScale = Time.timeScale;
            originalCursorLock = Cursor.lockState;
            originalCursorVisible = Cursor.visible;

            Time.timeScale = 1f;
            Physics.gravity = Vector3.down * 9.81f;
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;

            Visuals.Init();
            CreateCourse();
            CreateSlock();
            SetupCamera();
        }

        void CreateCourse()
        {
            var board = new GameObject("Tilting physics course");
            boardBody = board.AddComponent<Rigidbody>();
            boardBody.isKinematic = true;
            boardBody.interpolation = RigidbodyInterpolation.Interpolate;

            contactMaterial = new PhysicsMaterial("Truth Test Contact")
            {
                staticFriction = 0.18f,
                dynamicFriction = 0.15f,
                bounciness = 0.03f,
                frictionCombine = PhysicsMaterialCombine.Average,
                bounceCombine = PhysicsMaterialCombine.Average,
            };

            Box(board.transform, "Start platform", new Vector3(0f, -0.25f, 3f),
                new Vector3(8f, 0.5f, 12f), Visuals.FloorTop);
            Box(board.transform, "Corridor floor", new Vector3(0f, -0.25f, 15f),
                new Vector3(4.5f, 0.5f, 12f), Visuals.FloorTop);
            Box(board.transform, "Left corridor wall", new Vector3(-2.4f, 0.8f, 15f),
                new Vector3(0.3f, 2.1f, 12f), Visuals.WallSide);
            Box(board.transform, "Right corridor wall", new Vector3(2.4f, 0.8f, 15f),
                new Vector3(0.3f, 2.1f, 12f), Visuals.WallSide);
            Box(board.transform, "Offset wall", new Vector3(-0.95f, 0.75f, 12.5f),
                new Vector3(2.2f, 1.5f, 0.35f), Visuals.WallSide);

            var ramp = Box(board.transform, "Ramp", new Vector3(0f, 0.72f, 25.45f),
                new Vector3(4.5f, 0.35f, 9f), Visuals.FloorTop);
            ramp.transform.localRotation = Quaternion.Euler(-12f, 0f, 0f);

            const float landingY = 1.61f;
            Box(board.transform, "Pit approach", new Vector3(0f, landingY, 30.65f),
                new Vector3(4.5f, 0.5f, 1.5f), Visuals.FloorTop);
            Box(board.transform, "Pit left rail", new Vector3(-1.9f, landingY, 33f),
                new Vector3(0.7f, 0.5f, 3.2f), Visuals.FloorTop);
            Box(board.transform, "Pit right rail", new Vector3(1.9f, landingY, 33f),
                new Vector3(0.7f, 0.5f, 3.2f), Visuals.FloorTop);
            Box(board.transform, "Pit exit", new Vector3(0f, landingY, 35.8f),
                new Vector3(4.5f, 0.5f, 2.4f), Visuals.FloorTop);

            const float pitWidth = 3.1f;
            const float pitWallHeight = 6.4f;
            const float pitWallY = -1.35f;
            Box(board.transform, "Pit left wall", new Vector3(-pitWidth * 0.5f, pitWallY, 33f),
                new Vector3(0.2f, pitWallHeight, 3.2f), Visuals.WallSide);
            Box(board.transform, "Pit right wall", new Vector3(pitWidth * 0.5f, pitWallY, 33f),
                new Vector3(0.2f, pitWallHeight, 3.2f), Visuals.WallSide);
            Box(board.transform, "Pit front wall", new Vector3(0f, pitWallY, 31.4f),
                new Vector3(pitWidth, pitWallHeight, 0.2f), Visuals.WallSide);
            Box(board.transform, "Pit back wall", new Vector3(0f, pitWallY, 34.6f),
                new Vector3(pitWidth, pitWallHeight, 0.2f), Visuals.WallSide);
            Box(board.transform, "Pit catch floor", new Vector3(0f, -4.8f, 33f),
                new Vector3(4.5f, 0.5f, 6f), Visuals.FloorTop);
        }

        GameObject Box(Transform parent, string name, Vector3 position, Vector3 size, Material visualMaterial)
        {
            var box = GameObject.CreatePrimitive(PrimitiveType.Cube);
            box.name = name;
            box.transform.SetParent(parent, false);
            box.transform.localPosition = position;
            box.transform.localScale = size;
            box.GetComponent<MeshRenderer>().sharedMaterial = visualMaterial;
            box.GetComponent<BoxCollider>().sharedMaterial = contactMaterial;
            return box;
        }

        void CreateSlock()
        {
            var slock = SlockController.Create();
            var controller = slock.GetComponent<SlockController>();
            controller.enabled = false;

            slockBody = slock.Body;
            var slockCollider = slock.GetComponent<BoxCollider>();
            var oldMaterial = slockCollider.sharedMaterial;
            slockCollider.sharedMaterial = contactMaterial;
            if (oldMaterial != null) Destroy(oldMaterial);

            slockBody.useGravity = true;
            slockBody.constraints = RigidbodyConstraints.None;
            slockBody.linearDamping = 0.02f;
            slockBody.angularDamping = 0.05f;
            slockBody.interpolation = RigidbodyInterpolation.Interpolate;
            slockBody.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            controller.ResetTo(new Vector3(0f, 0.6f, 0f));
        }

        void SetupCamera()
        {
            testCamera = Camera.main;
            if (testCamera == null)
            {
                var cameraObject = new GameObject("Main Camera") { tag = "MainCamera" };
                testCamera = cameraObject.AddComponent<Camera>();
                cameraObject.AddComponent<AudioListener>();
            }

            cameraRig = testCamera.GetComponent<TiltCameraRig>();
            if (cameraRig != null)
            {
                cameraRigWasEnabled = cameraRig.enabled;
                cameraRig.enabled = false;
            }

            testCamera.clearFlags = CameraClearFlags.SolidColor;
            testCamera.backgroundColor = new Color(0.12f, 0.15f, 0.18f);
            testCamera.fieldOfView = 52f;
            testCamera.farClipPlane = 250f;

            var sun = RenderSettings.sun;
            if (sun == null) sun = new GameObject("Truth Test Sun").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            sun.intensity = 1.25f;
            sun.shadows = LightShadows.Soft;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.32f, 0.32f, 0.34f);
            RenderSettings.fog = false;
        }

        void Update()
        {
            ReadBoardInput();
            if (Keyboard.current != null && Keyboard.current.rKey.wasPressedThisFrame) ResetTest();
        }

        void ReadBoardInput()
        {
            var pad = Gamepad.current;
            var padInput = pad != null ? pad.leftStick.ReadUnprocessedValue() : Vector2.zero;
            if (padInput.sqrMagnitude > 0.000001f)
            {
                boardInput = Vector2.ClampMagnitude(padInput, 1f);
                return;
            }

            var keyboard = Keyboard.current;
            if (keyboard != null)
            {
                var trim = new Vector2(
                    (keyboard.rightArrowKey.isPressed ? 1f : 0f) - (keyboard.leftArrowKey.isPressed ? 1f : 0f),
                    (keyboard.upArrowKey.isPressed ? 1f : 0f) - (keyboard.downArrowKey.isPressed ? 1f : 0f));
                if (trim.sqrMagnitude > 0f)
                {
                    boardInput = Vector2.ClampMagnitude(boardInput + trim * (Time.unscaledDeltaTime * 0.8f), 1f);
                    return;
                }
            }

            if (Mouse.current != null)
                boardInput = Vector2.ClampMagnitude(boardInput + Mouse.current.delta.ReadValue() / MousePixelsForFullTilt, 1f);
        }

        void FixedUpdate()
        {
            var rotation = Quaternion.Euler(-boardInput.y * BoardTiltLimit, 0f, -boardInput.x * BoardTiltLimit);
            boardBody.MoveRotation(rotation);
        }

        void LateUpdate()
        {
            if (testCamera == null || slockBody == null) return;
            var target = slockBody.position;
            testCamera.transform.position = target + new Vector3(0f, 7f, -11f);
            testCamera.transform.LookAt(target + new Vector3(0f, 0f, 3f));
        }

        void ResetTest()
        {
            boardInput = Vector2.zero;
            boardBody.position = Vector3.zero;
            boardBody.rotation = Quaternion.identity;
            slockBody.position = new Vector3(0f, 0.6f, 0f);
            slockBody.rotation = Quaternion.identity;
            slockBody.linearVelocity = Vector3.zero;
            slockBody.angularVelocity = Vector3.zero;
        }

        void OnGUI()
        {
            var velocity = slockBody != null ? slockBody.linearVelocity : Vector3.zero;
            GUI.Box(new Rect(12f, 12f, 340f, 82f),
                $"PHYSICS TRUTH TEST\nMouse: tilt | Arrows: trim | Left stick: tilt | R: reset\n" +
                $"Board {boardInput.x:+0.00;-0.00;0}, {boardInput.y:+0.00;-0.00;0}   Slock speed {velocity.magnitude:0.00} m/s");
        }

        void OnDestroy()
        {
            Physics.gravity = originalGravity;
            Time.timeScale = originalTimeScale;
            Cursor.lockState = originalCursorLock;
            Cursor.visible = originalCursorVisible;
            if (cameraRig != null) cameraRig.enabled = cameraRigWasEnabled;
            if (contactMaterial != null) Destroy(contactMaterial);
        }
    }
}
