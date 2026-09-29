using UnityEditor;

namespace Slock.Editor
{
    public static class SlockPhysicsTruthTestMenu
    {
        [MenuItem("Slock/Play Physics Truth Test")]
        static void PlayPhysicsTruthTest()
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) return;

            SessionState.SetBool(SlockPhysicsTruthTest.EditorSessionKey, true);
            EditorApplication.isPlaying = true;
        }
    }
}
