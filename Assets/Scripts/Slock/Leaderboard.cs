using System;
using System.Collections.Generic;
using UnityEngine;

namespace Slock
{
    [Serializable]
    public class LeaderboardEntry
    {
        public string name;
        public int score;
        public int height;
        public float seconds;
        public string date;
    }

    /// <summary>Local top-10 stored in PlayerPrefs. Kept behind this API so an online board can slot in later.</summary>
    public static class Leaderboard
    {
        public const int Max = 10;
        const string Key = "slock.leaderboard.v1";

        [Serializable] class Save { public List<LeaderboardEntry> entries = new(); }

        public static List<LeaderboardEntry> Load()
        {
            var json = PlayerPrefs.GetString(Key, "");
            if (string.IsNullOrEmpty(json)) return new List<LeaderboardEntry>();
            try { return JsonUtility.FromJson<Save>(json)?.entries ?? new List<LeaderboardEntry>(); }
            catch { return new List<LeaderboardEntry>(); }
        }

        public static bool Qualifies(int score)
        {
            if (score <= 0) return false;
            var list = Load();
            return list.Count < Max || score > list[^1].score;
        }

        /// <summary>Inserts the entry and returns its 1-based rank, or 0 if it didn't make the board.</summary>
        public static int Submit(LeaderboardEntry entry)
        {
            var list = Load();
            list.Add(entry);
            list.Sort((a, b) => b.score.CompareTo(a.score));
            if (list.Count > Max) list.RemoveRange(Max, list.Count - Max);
            PlayerPrefs.SetString(Key, JsonUtility.ToJson(new Save { entries = list }));
            PlayerPrefs.Save();
            return list.IndexOf(entry) + 1;
        }
    }
}
