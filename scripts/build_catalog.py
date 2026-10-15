"""Build the app's bundled exercise catalog from free-exercise-db (public domain).

Usage: python3 -I build_catalog.py <exercises.json> <output.json>
"""
import json
import re
import sys

MUSCLE = {
    "abdominals": "abs", "abductors": "abductors", "adductors": "adductors", "biceps": "biceps",
    "calves": "calves", "chest": "chest", "forearms": "forearms", "glutes": "glutes",
    "hamstrings": "hamstrings", "lats": "lats", "lower back": "lowerBack", "middle back": "upperBack",
    "neck": "neck", "quadriceps": "quads", "shoulders": "shoulders", "traps": "traps", "triceps": "triceps",
}

CATEGORY = {
    "strength": "strength", "stretching": "stretching", "plyometrics": "plyometrics",
    "powerlifting": "powerlifting", "olympic weightlifting": "olympic", "strongman": "strongman",
    "cardio": "cardio",
}

# Popular exercises get clean names, rank first in search, and power the starter templates.
POPULAR = {
    # Chest
    "Barbell_Bench_Press_-_Medium_Grip": "Bench Press (Barbell)",
    "Barbell_Incline_Bench_Press_-_Medium_Grip": "Incline Bench Press (Barbell)",
    "Decline_Barbell_Bench_Press": "Decline Bench Press (Barbell)",
    "Dumbbell_Bench_Press": "Bench Press (Dumbbell)",
    "Incline_Dumbbell_Press": "Incline Bench Press (Dumbbell)",
    "Decline_Dumbbell_Bench_Press": "Decline Bench Press (Dumbbell)",
    "Close-Grip_Barbell_Bench_Press": "Close-Grip Bench Press",
    "Smith_Machine_Bench_Press": "Bench Press (Smith Machine)",
    "Smith_Machine_Incline_Bench_Press": "Incline Bench Press (Smith Machine)",
    "Machine_Bench_Press": "Chest Press (Machine)",
    "Leverage_Incline_Chest_Press": "Incline Chest Press (Machine)",
    "Dumbbell_Flyes": "Chest Fly (Dumbbell)",
    "Incline_Dumbbell_Flyes": "Incline Chest Fly (Dumbbell)",
    "Butterfly": "Pec Deck (Machine)",
    "Cable_Crossover": "Cable Crossover",
    "Incline_Cable_Flye": "Incline Cable Fly",
    "Pushups": "Push-Up",
    "Dips_-_Chest_Version": "Chest Dip",
    "Straight-Arm_Dumbbell_Pullover": "Pullover (Dumbbell)",
    # Back
    "Barbell_Deadlift": "Deadlift (Barbell)",
    "Sumo_Deadlift": "Sumo Deadlift",
    "Trap_Bar_Deadlift": "Trap Bar Deadlift",
    "Rack_Pulls": "Rack Pull",
    "Bent_Over_Barbell_Row": "Bent Over Row (Barbell)",
    "One-Arm_Dumbbell_Row": "Single-Arm Row (Dumbbell)",
    "Bent_Over_Two-Dumbbell_Row": "Bent Over Row (Dumbbell)",
    "T-Bar_Row_with_Handle": "T-Bar Row",
    "Seated_Cable_Rows": "Seated Cable Row",
    "Seated_One-arm_Cable_Pulley_Rows": "Single-Arm Cable Row",
    "Leverage_Iso_Row": "Row (Machine)",
    "Leverage_High_Row": "High Row (Machine)",
    "Wide-Grip_Lat_Pulldown": "Lat Pulldown",
    "Close-Grip_Front_Lat_Pulldown": "Close-Grip Lat Pulldown",
    "V-Bar_Pulldown": "V-Bar Pulldown",
    "One_Arm_Lat_Pulldown": "Single-Arm Lat Pulldown",
    "Pullups": "Pull-Up",
    "Chin-Up": "Chin-Up",
    "Weighted_Pull_Ups": "Weighted Pull-Up",
    "Straight-Arm_Pulldown": "Straight-Arm Pulldown",
    "Hyperextensions_Back_Extensions": "Back Extension",
    "Dumbbell_Incline_Row": "Chest-Supported Row (Dumbbell)",
    "Barbell_Shrug": "Shrug (Barbell)",
    "Dumbbell_Shrug": "Shrug (Dumbbell)",
    # Shoulders
    "Standing_Military_Press": "Overhead Press (Barbell)",
    "Seated_Barbell_Military_Press": "Seated Overhead Press (Barbell)",
    "Dumbbell_Shoulder_Press": "Shoulder Press (Dumbbell)",
    "Seated_Dumbbell_Press": "Seated Shoulder Press (Dumbbell)",
    "Machine_Shoulder_Military_Press": "Shoulder Press (Machine)",
    "Smith_Machine_Overhead_Shoulder_Press": "Shoulder Press (Smith Machine)",
    "Arnold_Dumbbell_Press": "Arnold Press",
    "Side_Lateral_Raise": "Lateral Raise (Dumbbell)",
    "Front_Dumbbell_Raise": "Front Raise (Dumbbell)",
    "Reverse_Flyes": "Rear Delt Fly (Dumbbell)",
    "Reverse_Machine_Flyes": "Reverse Pec Deck",
    "Cable_Rear_Delt_Fly": "Rear Delt Fly (Cable)",
    "Face_Pull": "Face Pull",
    "Upright_Barbell_Row": "Upright Row (Barbell)",
    # Arms
    "Barbell_Curl": "Bicep Curl (Barbell)",
    "Dumbbell_Bicep_Curl": "Bicep Curl (Dumbbell)",
    "Dumbbell_Alternate_Bicep_Curl": "Alternating Bicep Curl (Dumbbell)",
    "Hammer_Curls": "Hammer Curl (Dumbbell)",
    "EZ-Bar_Curl": "Bicep Curl (EZ Bar)",
    "Preacher_Curl": "Preacher Curl (Barbell)",
    "One_Arm_Dumbbell_Preacher_Curl": "Preacher Curl (Dumbbell)",
    "Machine_Preacher_Curls": "Preacher Curl (Machine)",
    "Incline_Dumbbell_Curl": "Incline Curl (Dumbbell)",
    "Dumbbell_Prone_Incline_Curl": "Spider Curl (Dumbbell)",
    "Concentration_Curls": "Concentration Curl",
    "Standing_Biceps_Cable_Curl": "Bicep Curl (Cable)",
    "Cable_Hammer_Curls_-_Rope_Attachment": "Hammer Curl (Cable)",
    "Reverse_Barbell_Curl": "Reverse Curl (Barbell)",
    "Triceps_Pushdown": "Triceps Pushdown",
    "Triceps_Pushdown_-_Rope_Attachment": "Triceps Rope Pushdown",
    "Cable_Rope_Overhead_Triceps_Extension": "Overhead Triceps Extension (Cable)",
    "EZ-Bar_Skullcrusher": "Skull Crusher (EZ Bar)",
    "Standing_Dumbbell_Triceps_Extension": "Overhead Triceps Extension (Dumbbell)",
    "Tricep_Dumbbell_Kickback": "Triceps Kickback (Dumbbell)",
    "Dips_-_Triceps_Version": "Triceps Dip",
    "Machine_Triceps_Extension": "Triceps Extension (Machine)",
    "Seated_Palm-Up_Barbell_Wrist_Curl": "Wrist Curl (Barbell)",
    # Legs
    "Barbell_Squat": "Squat (Barbell)",
    "Front_Squat_Clean_Grip": "Front Squat (Barbell)",
    "Goblet_Squat": "Goblet Squat",
    "Hack_Squat": "Hack Squat",
    "Smith_Machine_Squat": "Squat (Smith Machine)",
    "Leg_Press": "Leg Press",
    "Leg_Extensions": "Leg Extension",
    "Lying_Leg_Curls": "Lying Leg Curl",
    "Seated_Leg_Curl": "Seated Leg Curl",
    "Romanian_Deadlift": "Romanian Deadlift (Barbell)",
    "Stiff-Legged_Dumbbell_Deadlift": "Romanian Deadlift (Dumbbell)",
    "Barbell_Hip_Thrust": "Hip Thrust (Barbell)",
    "Barbell_Glute_Bridge": "Glute Bridge (Barbell)",
    "Dumbbell_Lunges": "Lunge (Dumbbell)",
    "Dumbbell_Rear_Lunge": "Reverse Lunge (Dumbbell)",
    "Barbell_Walking_Lunge": "Walking Lunge (Barbell)",
    "Bodyweight_Walking_Lunge": "Walking Lunge",
    "Split_Squat_with_Dumbbells": "Split Squat (Dumbbell)",
    "Dumbbell_Step_Ups": "Step-Up (Dumbbell)",
    "Good_Morning": "Good Morning",
    "Glute_Ham_Raise": "Glute-Ham Raise",
    "Standing_Calf_Raises": "Standing Calf Raise (Machine)",
    "Seated_Calf_Raise": "Seated Calf Raise",
    "Calf_Press_On_The_Leg_Press_Machine": "Calf Press (Leg Press)",
    "Cable_Hip_Adduction": "Hip Adduction (Cable)",
    "Bodyweight_Squat": "Air Squat",
    # Core
    "Plank": "Plank",
    "Hanging_Leg_Raise": "Hanging Leg Raise",
    "Cable_Crunch": "Cable Crunch",
    "Ab_Roller": "Ab Wheel Rollout",
    "Crunches": "Crunch",
    "Russian_Twist": "Russian Twist",
    "Ab_Crunch_Machine": "Ab Crunch (Machine)",
    "Decline_Crunch": "Decline Crunch",
    "Mountain_Climbers": "Mountain Climber",
    # Other
    "Power_Clean": "Power Clean",
    "Farmers_Walk": "Farmer's Walk",
}

ALIASES = {
    "Barbell_Bench_Press_-_Medium_Grip": ["bb bench", "flat bench"],
    "Standing_Military_Press": ["ohp", "military press"],
    "Romanian_Deadlift": ["rdl"],
    "Stiff-Legged_Dumbbell_Deadlift": ["db rdl", "stiff leg deadlift"],
    "Butterfly": ["machine fly", "butterfly"],
    "EZ-Bar_Skullcrusher": ["lying triceps extension"],
    "Wide-Grip_Lat_Pulldown": ["pulldown", "lat pull down"],
    "Barbell_Squat": ["back squat"],
    "Pullups": ["pullup", "pull up"],
    "Chin-Up": ["chinup", "chin up"],
    "Pushups": ["pushup", "push up", "press up"],
    "Leg_Extensions": ["quad extension"],
    "Lying_Leg_Curls": ["hamstring curl"],
    "Seated_Leg_Curl": ["hamstring curl"],
    "Face_Pull": ["rear delt"],
    "Barbell_Hip_Thrust": ["glute thrust"],
    "Hyperextensions_Back_Extensions": ["hyperextension"],
    "Farmers_Walk": ["farmer carry", "loaded carry"],
}

# Modern staples that free-exercise-db does not include.
EXTRAS = [
    ("forge_bulgarian_split_squat", "Bulgarian Split Squat (Dumbbell)", ["quads"], ["glutes", "hamstrings"], "dumbbell", "strength", "compound", "push", [
        "Stand a stride in front of a bench and rest the top of your back foot on it.",
        "Hold a dumbbell in each hand with your torso tall.",
        "Lower until your rear knee nearly touches the floor and your front thigh is about parallel.",
        "Drive through your front heel to stand back up. Finish all reps, then switch legs."]),
    ("forge_cable_lateral_raise", "Lateral Raise (Cable)", ["shoulders"], ["traps"], "cable", "strength", "isolation", "push", [
        "Set a pulley at its lowest position and stand side-on to the stack.",
        "Grab the handle with the far hand, arm slightly bent across your body.",
        "Raise your arm out to the side until it is level with your shoulder.",
        "Lower slowly under control and repeat, then switch sides."]),
    ("forge_machine_lateral_raise", "Lateral Raise (Machine)", ["shoulders"], [], "machine", "strength", "isolation", "push", [
        "Adjust the seat so your shoulders line up with the machine's pivot point.",
        "Place your forearms or hands against the pads.",
        "Raise your arms out to the sides until they reach shoulder height.",
        "Lower slowly and repeat."]),
    ("forge_pendulum_squat", "Pendulum Squat", ["quads"], ["glutes", "adductors"], "machine", "strength", "compound", "push", [
        "Step into the machine with your back against the pad and shoulders under the pads.",
        "Place your feet mid-platform, about shoulder-width apart.",
        "Release the safety and squat down as deep as you can control.",
        "Drive through the whole foot to return to the top."]),
    ("forge_hip_abduction_machine", "Hip Abduction (Machine)", ["abductors"], ["glutes"], "machine", "strength", "isolation", "push", [
        "Sit in the machine with the pads against the outside of your knees.",
        "Push your knees outward as far as you can control.",
        "Pause briefly, then return slowly to the start."]),
    ("forge_hip_adduction_machine", "Hip Adduction (Machine)", ["adductors"], [], "machine", "strength", "isolation", "pull", [
        "Sit in the machine with the pads against the inside of your knees.",
        "Squeeze your legs together until the pads meet.",
        "Pause briefly, then return slowly to the start."]),
    ("forge_assisted_pullup", "Assisted Pull-Up (Machine)", ["lats"], ["biceps", "upperBack"], "machine", "strength", "compound", "pull", [
        "Select the assistance weight, then kneel or stand on the platform.",
        "Grip the handles slightly wider than shoulder-width.",
        "Pull until your chin clears the handles, driving your elbows down.",
        "Lower under control to a full hang."]),
    ("forge_chest_supported_tbar_row", "Chest-Supported T-Bar Row", ["upperBack"], ["lats", "biceps", "shoulders"], "machine", "strength", "compound", "pull", [
        "Lie face down on the pad with your chest supported.",
        "Grab the handles and lift the weight off the rack.",
        "Row the handles toward your torso, squeezing your shoulder blades together.",
        "Lower until your arms are fully extended."]),
    ("forge_bayesian_curl", "Bayesian Curl (Cable)", ["biceps"], ["forearms"], "cable", "strength", "isolation", "pull", [
        "Set a pulley low and face away from it, holding the handle behind you.",
        "Stagger your stance with your arm extended behind your torso.",
        "Curl the handle forward and up while keeping your elbow back.",
        "Lower slowly to a full stretch."]),
    ("forge_nordic_curl", "Nordic Hamstring Curl", ["hamstrings"], ["glutes"], "body only", "strength", "isolation", "pull", [
        "Kneel on a pad with your ankles anchored under something sturdy.",
        "Keeping your hips extended, lower your torso toward the floor as slowly as possible.",
        "Catch yourself with your hands, then pull back up using your hamstrings."]),
    ("forge_belt_squat", "Belt Squat", ["quads"], ["glutes", "adductors"], "machine", "strength", "compound", "push", [
        "Attach the belt around your hips and stand on the platform.",
        "Release the weight and squat down with an upright torso.",
        "Drive through your feet to stand back up."]),
    ("forge_landmine_press", "Landmine Press", ["shoulders"], ["chest", "triceps"], "barbell", "strength", "compound", "push", [
        "Hold the end of a landmine barbell at shoulder height.",
        "Press the bar up and forward until your arm is extended.",
        "Lower under control back to your shoulder."]),
    ("forge_kettlebell_swing", "Kettlebell Swing", ["glutes"], ["hamstrings", "lowerBack", "shoulders"], "kettlebells", "strength", "compound", "pull", [
        "Stand with feet shoulder-width apart and the kettlebell just in front of you.",
        "Hinge at the hips, hike the bell back between your legs.",
        "Snap your hips forward to swing the bell to chest height.",
        "Let it fall back into the hinge and repeat."]),
    ("forge_machine_hip_thrust", "Hip Thrust (Machine)", ["glutes"], ["hamstrings"], "machine", "strength", "compound", "push", [
        "Sit in the machine with your upper back on the pad and the belt across your hips.",
        "Plant your feet flat, about shoulder-width apart.",
        "Drive your hips up until they are fully extended and squeeze your glutes.",
        "Lower slowly and repeat."]),
    ("forge_cable_glute_kickback", "Glute Kickback (Cable)", ["glutes"], ["hamstrings"], "cable", "strength", "isolation", "push", [
        "Attach an ankle strap to a low pulley and face the stack.",
        "Brace on the frame and kick your strapped leg straight back.",
        "Squeeze your glute at the top, then return under control."]),
    ("forge_seal_row", "Seal Row", ["upperBack"], ["lats", "biceps"], "barbell", "strength", "compound", "pull", [
        "Lie face down on an elevated bench with a barbell underneath.",
        "Grab the bar slightly wider than shoulder-width.",
        "Row the bar to the underside of the bench, squeezing your shoulder blades.",
        "Lower to a full stretch."]),
    ("forge_pendlay_row", "Pendlay Row", ["upperBack"], ["lats", "biceps", "lowerBack"], "barbell", "strength", "compound", "pull", [
        "Set up with a flat back, torso nearly parallel to the floor, bar on the ground.",
        "Explosively row the bar to your lower chest.",
        "Return the bar to the floor and reset each rep."]),
    ("forge_meadows_row", "Meadows Row", ["lats"], ["upperBack", "biceps"], "barbell", "strength", "compound", "pull", [
        "Stand perpendicular to a landmine barbell and grip the end of the bar overhand.",
        "Stagger your stance and hinge forward.",
        "Row the bar up toward your hip, driving your elbow high.",
        "Lower under control and repeat, then switch sides."]),
    ("forge_dead_hang", "Dead Hang", ["forearms"], ["lats", "shoulders"], "body only", "strength", "isolation", "pull", [
        "Grab a pull-up bar with a shoulder-width overhand grip.",
        "Hang with your arms straight and shoulders engaged.",
        "Hold for time."]),
    ("forge_wall_sit", "Wall Sit", ["quads"], ["glutes"], "body only", "strength", "isolation", "push", [
        "Lean your back against a wall and slide down until your thighs are parallel to the floor.",
        "Keep your knees over your ankles.",
        "Hold for time."]),
    ("forge_side_plank", "Side Plank", ["abs"], ["glutes", "shoulders"], "body only", "strength", "isolation", "static", [
        "Lie on your side and prop yourself up on your forearm.",
        "Lift your hips so your body forms a straight line.",
        "Hold for time, then switch sides."]),
    ("forge_dead_bug", "Dead Bug", ["abs"], [], "body only", "strength", "isolation", "static", [
        "Lie on your back with arms reaching up and knees bent at 90 degrees.",
        "Press your lower back into the floor.",
        "Extend the opposite arm and leg toward the floor, then return.",
        "Alternate sides each rep."]),
    ("forge_pallof_press", "Pallof Press", ["abs"], ["shoulders"], "cable", "strength", "isolation", "static", [
        "Stand side-on to a cable set at chest height, holding the handle at your chest.",
        "Press the handle straight out in front of you, resisting rotation.",
        "Bring it back to your chest and repeat, then switch sides."]),
    ("forge_captains_chair_leg_raise", "Leg Raise (Captain's Chair)", ["abs"], [], "body only", "strength", "isolation", "pull", [
        "Support yourself on the captain's chair with your back against the pad.",
        "Raise your knees or straight legs toward your chest.",
        "Lower under control without swinging."]),
    ("forge_copenhagen_plank", "Copenhagen Plank", ["adductors"], ["abs"], "body only", "strength", "isolation", "static", [
        "Lie on your side with your top leg resting on a bench.",
        "Lift your hips so your body forms a straight line, supported by your top leg.",
        "Hold for time, then switch sides."]),
    ("forge_smith_hip_thrust", "Hip Thrust (Smith Machine)", ["glutes"], ["hamstrings"], "machine", "strength", "compound", "push", [
        "Sit with your upper back against a bench and the Smith bar across your hips.",
        "Unrack and drive your hips up until fully extended.",
        "Lower slowly and repeat."]),
    ("forge_incline_walk", "Incline Treadmill Walk", ["quads"], ["glutes", "calves"], "machine", "cardio", None, None, [
        "Set the treadmill to an incline between 8 and 15 percent.",
        "Walk at a steady pace without holding the handrails.",
        "Track time."]),
]

DURATION_WORDS = re.compile(r"\b(plank|hold|wall sit|dead hang|isometric)\b", re.I)


def equipment_for(raw_equipment, name):
    if "smith" in name.lower():
        return "smithMachine"
    return {
        "barbell": "barbell", "dumbbell": "dumbbell", "cable": "cable", "machine": "machine",
        "body only": "bodyweight", None: "bodyweight", "kettlebells": "kettlebell", "bands": "band",
        "e-z curl bar": "ezBar", "medicine ball": "medicineBall", "exercise ball": "exerciseBall",
        "foam roll": "foamRoll", "other": "other",
    }[raw_equipment]


def tracking_for(category, equipment, name):
    if category in ("stretching", "cardio"):
        return "duration"
    if DURATION_WORDS.search(name):
        return "duration"
    if equipment == "bodyweight" and "weighted" not in name.lower():
        return "bodyweight"
    return "weightReps"


def clean_name(name):
    name = re.sub(r"\s+", " ", name).strip()
    return name


def main():
    src, out = sys.argv[1], sys.argv[2]
    data = json.load(open(src))
    seen = set()
    result = []
    missing = [k for k in POPULAR if k not in {d["id"] for d in data}]
    if missing:
        print("missing popular ids:", missing)
    for d in data:
        ex_id = d["id"]
        if ex_id in seen:
            continue
        seen.add(ex_id)
        original = clean_name(d["name"])
        name = POPULAR.get(ex_id, original)
        category = CATEGORY[d["category"]]
        equipment = equipment_for(d["equipment"], original)
        aliases = list(ALIASES.get(ex_id, []))
        if name != original:
            aliases.append(original)
        primary = list(dict.fromkeys(MUSCLE[m] for m in d["primaryMuscles"]))
        secondary = [m for m in dict.fromkeys(MUSCLE[m] for m in d["secondaryMuscles"]) if m not in primary]
        entry = {
            "id": ex_id,
            "n": name,
            "p": primary,
            "s": secondary,
            "e": equipment,
            "c": category,
            "t": tracking_for(category, equipment, name),
            "i": [s.strip() for s in d["instructions"] if s.strip()],
        }
        if d.get("level"):
            entry["l"] = d["level"]
        if d.get("mechanic"):
            entry["m"] = d["mechanic"]
        if aliases:
            entry["a"] = aliases
        if ex_id in POPULAR:
            entry["pop"] = 1
        result.append(entry)
    for ex_id, name, primary, secondary, eq, cat, mech, force, steps in EXTRAS:
        equipment = equipment_for(eq, name)
        entry = {
            "id": ex_id, "n": name, "p": primary, "s": secondary, "e": equipment, "c": cat,
            "t": tracking_for(cat, equipment, name), "i": steps, "pop": 1,
        }
        if mech:
            entry["m"] = mech
        result.append(entry)
    result.sort(key=lambda e: e["n"].lower())
    with open(out, "w") as f:
        json.dump(result, f, separators=(",", ":"), ensure_ascii=False)
    print(len(result), "exercises,", sum(1 for e in result if e.get("pop")), "popular")
    from collections import Counter
    print(Counter(e["t"] for e in result))


if __name__ == "__main__":
    main()
