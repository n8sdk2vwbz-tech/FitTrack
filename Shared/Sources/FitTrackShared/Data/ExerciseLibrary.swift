import Foundation

/// Statische Übungsbibliothek, auf iPhone und Watch identisch verfügbar.
public enum ExerciseLibrary {

    public static let all: [Exercise] = [
        // MARK: Brust
        Exercise(id: "bench-press-barbell", name: "Bankdrücken (Langhantel)", category: .strength, equipment: .barbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders], instructions: "Langhantel auf der Flachbank zur Brust senken und explosiv nach oben drücken."),
        Exercise(id: "smith-machine-bench-press", name: "Bankdrücken (Smith Machine)", category: .strength, equipment: .machine, primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders], instructions: "Stange in der geführten Bahn zur Brust senken und hochdrücken."),
        Exercise(id: "bench-press-dumbbell", name: "Bankdrücken (Kurzhantel)", category: .strength, equipment: .dumbbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders], instructions: "Kurzhanteln auf Brusthöhe senken, kontrolliert nach oben drücken."),
        Exercise(id: "incline-bench-press", name: "Schrägbankdrücken", category: .strength, equipment: .barbell, primaryMuscles: [.chest], secondaryMuscles: [.shoulders, .triceps], instructions: "Auf der Schrägbank (30-45°) die Langhantel zur oberen Brust senken."),
        Exercise(id: "dumbbell-fly", name: "Kurzhantel Fliegende", category: .strength, equipment: .dumbbell, primaryMuscles: [.chest], secondaryMuscles: [.shoulders], instructions: "Mit leicht gebeugten Armen die Kurzhanteln seitlich absenken und die Brust zusammenziehen."),
        Exercise(id: "pec-deck", name: "Butterfly Maschine", category: .strength, equipment: .machine, primaryMuscles: [.chest], secondaryMuscles: [], instructions: "Arme vor der Brust zusammenführen, Bewegung kontrolliert zurückführen."),
        Exercise(id: "push-up", name: "Liegestütze", category: .strength, equipment: .bodyweight, primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders, .abs], instructions: "Körper gerade halten, Brust Richtung Boden senken, hochdrücken."),
        Exercise(id: "chest-dip", name: "Dips (Brustfokus)", category: .strength, equipment: .bodyweight, primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders], instructions: "Oberkörper nach vorne geneigt tief absenken, um die Brust stärker einzubinden."),
        Exercise(id: "cable-crossover", name: "Cable Crossover", category: .strength, equipment: .cable, primaryMuscles: [.chest], secondaryMuscles: [.shoulders], instructions: "Kabelzüge von oben nach unten vor dem Körper zusammenführen."),
        Exercise(id: "decline-bench-press", name: "Negativ-Bankdrücken", category: .strength, equipment: .barbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps], instructions: "Auf der Negativbank die Langhantel zur unteren Brust senken."),
        Exercise(id: "svend-press", name: "Svend Press", category: .strength, equipment: .dumbbell, primaryMuscles: [.chest], secondaryMuscles: [.shoulders], instructions: "Gewichtsscheibe vor der Brust zusammenpressen und nach vorne drücken."),
        Exercise(id: "chest-press-machine", name: "Bankdrücken an der Maschine", category: .strength, equipment: .machine, primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders], instructions: "Griffe gleichmäßig nach vorne drücken, kontrolliert zurückführen."),

        // MARK: Rücken
        Exercise(id: "pull-up", name: "Klimmzüge", category: .strength, equipment: .bodyweight, primaryMuscles: [.lats], secondaryMuscles: [.biceps, .upperBack], instructions: "Am Klimmzugstab hochziehen, bis das Kinn über der Stange ist."),
        Exercise(id: "weighted-pull-up", name: "Klimmzüge mit Zusatzgewicht", category: .strength, equipment: .bodyweight, primaryMuscles: [.lats], secondaryMuscles: [.biceps, .upperBack], instructions: "Zusatzgewicht an Gurt/Kettel befestigen, wie einen normalen Klimmzug ausführen.", loadType: .bodyweightPlus),
        Exercise(id: "assisted-pull-up-machine", name: "Klimmzüge an der Maschine (unterstützt)", category: .strength, equipment: .machine, primaryMuscles: [.lats], secondaryMuscles: [.biceps, .upperBack], instructions: "Eingegebenes Gewicht ist die Unterstützung durch das Gegengewicht - je höher, desto leichter die Wiederholung.", loadType: .bodyweightMinus),
        Exercise(id: "lat-pulldown", name: "Latzug", category: .strength, equipment: .cable, primaryMuscles: [.lats], secondaryMuscles: [.biceps, .upperBack], instructions: "Stange zur oberen Brust ziehen, Schulterblätter zusammenziehen."),
        Exercise(id: "barbell-row", name: "Rudern vorgebeugt (Langhantel)", category: .strength, equipment: .barbell, primaryMuscles: [.upperBack, .lats], secondaryMuscles: [.biceps], instructions: "Oberkörper vorgebeugt, Langhantel zum Bauchnabel ziehen."),
        Exercise(id: "one-arm-dumbbell-row", name: "Kurzhantel Rudern einarmig", category: .strength, equipment: .dumbbell, primaryMuscles: [.upperBack, .lats], secondaryMuscles: [.biceps], instructions: "Auf Bank abstützen, Kurzhantel seitlich zur Hüfte ziehen. Eingegebenes Gewicht gilt pro Seite.", isUnilateral: true),
        Exercise(id: "seated-cable-row", name: "Kabelrudern sitzend", category: .strength, equipment: .cable, primaryMuscles: [.upperBack], secondaryMuscles: [.lats, .biceps], instructions: "Griff zum Bauch ziehen, Rücken aufrecht halten."),
        Exercise(id: "machine-row", name: "Rudern an der Maschine", category: .strength, equipment: .machine, primaryMuscles: [.upperBack], secondaryMuscles: [.lats, .biceps], instructions: "Griffe zum Körper ziehen, Schulterblätter zusammenführen."),
        Exercise(id: "t-bar-row", name: "T-Bar Rudern", category: .strength, equipment: .barbell, primaryMuscles: [.upperBack, .lats], secondaryMuscles: [.biceps], instructions: "Vorgebeugt die T-Bar-Stange zum Oberkörper ziehen."),
        Exercise(id: "deadlift", name: "Kreuzheben", category: .strength, equipment: .barbell, primaryMuscles: [.lowerBack, .hamstrings, .glutes], secondaryMuscles: [.upperBack, .forearms], instructions: "Langhantel mit geradem Rücken vom Boden aufnehmen und aufrichten."),
        Exercise(id: "superman", name: "Superman", category: .strength, equipment: .bodyweight, primaryMuscles: [.lowerBack], secondaryMuscles: [.glutes], instructions: "Bauchlage, Arme und Beine gleichzeitig vom Boden abheben."),
        Exercise(id: "back-extension", name: "Rückenstrecker Maschine", category: .strength, equipment: .machine, primaryMuscles: [.lowerBack], secondaryMuscles: [.glutes, .hamstrings], instructions: "Oberkörper aus der Beugung kontrolliert aufrichten."),
        Exercise(id: "face-pull", name: "Face Pulls", category: .strength, equipment: .cable, primaryMuscles: [.traps, .shoulders], secondaryMuscles: [.upperBack], instructions: "Seil zum Gesicht ziehen, Ellenbogen hoch, Schulterblätter zusammen."),

        // MARK: Schultern
        Exercise(id: "overhead-press-barbell", name: "Schulterdrücken (Langhantel)", category: .strength, equipment: .barbell, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps], instructions: "Langhantel von der Schulter über den Kopf drücken."),
        Exercise(id: "overhead-press-dumbbell", name: "Kurzhantel Schulterdrücken", category: .strength, equipment: .dumbbell, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps], instructions: "Kurzhanteln von Schulterhöhe nach oben drücken."),
        Exercise(id: "lateral-raise", name: "Seitheben", category: .strength, equipment: .dumbbell, primaryMuscles: [.shoulders], secondaryMuscles: [], instructions: "Arme seitlich bis Schulterhöhe anheben, leicht gebeugt."),
        Exercise(id: "front-raise", name: "Frontheben", category: .strength, equipment: .dumbbell, primaryMuscles: [.shoulders], secondaryMuscles: [], instructions: "Kurzhantel vor dem Körper bis Schulterhöhe anheben."),
        Exercise(id: "arnold-press", name: "Arnold Press", category: .strength, equipment: .dumbbell, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps], instructions: "Rotierende Druckbewegung von vor der Brust nach oben."),
        Exercise(id: "reverse-fly", name: "Reverse Flys", category: .strength, equipment: .dumbbell, primaryMuscles: [.shoulders], secondaryMuscles: [.upperBack], instructions: "Vorgebeugt Kurzhanteln seitlich nach hinten oben führen."),
        Exercise(id: "cable-lateral-raise", name: "Kabel Seitheben", category: .strength, equipment: .cable, primaryMuscles: [.shoulders], secondaryMuscles: [], instructions: "Kabelzug seitlich am gestreckten Arm nach oben führen."),
        Exercise(id: "cable-lateral-raise-single-arm", name: "Kabel Seitheben einarmig", category: .strength, equipment: .cable, primaryMuscles: [.shoulders], secondaryMuscles: [], instructions: "Eine Seite isoliert seitlich hochführen, Kabelzug von der Körpermitte. Eingegebenes Gewicht gilt pro Seite.", isUnilateral: true),
        Exercise(id: "military-press", name: "Military Press", category: .strength, equipment: .barbell, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps, .abs], instructions: "Strikt stehend die Langhantel über Kopf drücken."),
        Exercise(id: "shoulder-press-machine", name: "Schulterdrücken an der Maschine", category: .strength, equipment: .machine, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps], instructions: "Griffe gleichmäßig nach oben drücken, kontrolliert absenken."),
        Exercise(id: "upright-row", name: "Aufrechtes Rudern", category: .strength, equipment: .barbell, primaryMuscles: [.shoulders, .traps], secondaryMuscles: [], instructions: "Langhantel eng am Körper bis zum Kinn hochziehen."),
        Exercise(id: "landmine-press", name: "Landmine Press", category: .strength, equipment: .barbell, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps, .chest], instructions: "Ende der eingespannten Langhantel diagonal nach oben drücken."),

        // MARK: Bizeps
        Exercise(id: "barbell-curl", name: "Bizepscurls (Langhantel)", category: .strength, equipment: .barbell, primaryMuscles: [.biceps], secondaryMuscles: [.forearms], instructions: "Langhantel mit Unterarmen zur Schulter curlen."),
        Exercise(id: "dumbbell-curl", name: "Kurzhantel Curls", category: .strength, equipment: .dumbbell, primaryMuscles: [.biceps], secondaryMuscles: [.forearms], instructions: "Kurzhanteln abwechselnd oder gleichzeitig zur Schulter curlen."),
        Exercise(id: "hammer-curl", name: "Hammer Curls", category: .strength, equipment: .dumbbell, primaryMuscles: [.biceps], secondaryMuscles: [.forearms], instructions: "Curl mit neutralem Griff, Handflächen zeigen zueinander."),
        Exercise(id: "concentration-curl", name: "Konzentrationscurls", category: .strength, equipment: .dumbbell, primaryMuscles: [.biceps], secondaryMuscles: [], instructions: "Ellenbogen am Oberschenkel abgestützt, isoliert curlen."),
        Exercise(id: "cable-curl", name: "Kabel Curls", category: .strength, equipment: .cable, primaryMuscles: [.biceps], secondaryMuscles: [.forearms], instructions: "Am Kabelzug mit konstanter Spannung curlen."),
        Exercise(id: "cable-curl-single-arm", name: "Kabel Curls einarmig", category: .strength, equipment: .cable, primaryMuscles: [.biceps], secondaryMuscles: [.forearms], instructions: "Eine Seite isoliert curlen, Ellenbogen fixiert. Eingegebenes Gewicht gilt pro Seite.", isUnilateral: true),
        Exercise(id: "preacher-curl", name: "Preacher Curls", category: .strength, equipment: .barbell, primaryMuscles: [.biceps], secondaryMuscles: [], instructions: "Arme auf der Schrägpolster-Bank fixiert curlen."),
        Exercise(id: "chin-up", name: "Chin-ups", category: .strength, equipment: .bodyweight, primaryMuscles: [.biceps, .lats], secondaryMuscles: [.upperBack], instructions: "Klimmzug im Untergriff, Fokus auf den Bizeps."),

        // MARK: Trizeps
        Exercise(id: "triceps-pushdown", name: "Trizepsdrücken (Kabel)", category: .strength, equipment: .cable, primaryMuscles: [.triceps], secondaryMuscles: [], instructions: "Seil oder Stange am Kabelzug nach unten drücken, Ellenbogen fixiert."),
        Exercise(id: "triceps-pushdown-single-arm", name: "Trizepsdrücken einarmig (Kabel)", category: .strength, equipment: .cable, primaryMuscles: [.triceps], secondaryMuscles: [], instructions: "Eine Seite isoliert nach unten drücken. Eingegebenes Gewicht gilt pro Seite.", isUnilateral: true),
        Exercise(id: "close-grip-bench-press", name: "Enges Bankdrücken", category: .strength, equipment: .barbell, primaryMuscles: [.triceps], secondaryMuscles: [.chest, .shoulders], instructions: "Langhantel im engen Griff zur Brust senken und drücken."),
        Exercise(id: "triceps-dip", name: "Trizeps Dips", category: .strength, equipment: .bodyweight, primaryMuscles: [.triceps], secondaryMuscles: [.chest, .shoulders], instructions: "Oberkörper aufrecht halten, Fokus auf die Streckung im Ellenbogen."),
        Exercise(id: "weighted-dip", name: "Dips mit Zusatzgewicht", category: .strength, equipment: .bodyweight, primaryMuscles: [.triceps], secondaryMuscles: [.chest, .shoulders], instructions: "Zusatzgewicht an Gurt/Kettel befestigen, wie einen normalen Dip ausführen.", loadType: .bodyweightPlus),
        Exercise(id: "assisted-dip-machine", name: "Dips an der Maschine (unterstützt)", category: .strength, equipment: .machine, primaryMuscles: [.triceps], secondaryMuscles: [.chest, .shoulders], instructions: "Eingegebenes Gewicht ist die Unterstützung durch das Gegengewicht - je höher, desto leichter die Wiederholung.", loadType: .bodyweightMinus),
        Exercise(id: "overhead-triceps-extension", name: "Overhead Extension (Kurzhantel)", category: .strength, equipment: .dumbbell, primaryMuscles: [.triceps], secondaryMuscles: [], instructions: "Kurzhantel hinter dem Kopf absenken und wieder strecken."),
        Exercise(id: "overhead-triceps-extension-cable", name: "Trizepsdrücken über Kopf (Kabel)", category: .strength, equipment: .cable, primaryMuscles: [.triceps], secondaryMuscles: [], instructions: "Seil am Kabelzug hinter dem Kopf absenken und über Kopf strecken."),
        Exercise(id: "skull-crusher", name: "Skullcrusher", category: .strength, equipment: .barbell, primaryMuscles: [.triceps], secondaryMuscles: [], instructions: "Langhantel liegend zur Stirn absenken, dann strecken."),
        Exercise(id: "triceps-kickback", name: "Kickbacks", category: .strength, equipment: .dumbbell, primaryMuscles: [.triceps], secondaryMuscles: [], instructions: "Vorgebeugt den Arm nach hinten strecken."),

        // MARK: Unterarme
        Exercise(id: "wrist-curl", name: "Handgelenkscurls", category: .strength, equipment: .barbell, primaryMuscles: [.forearms], secondaryMuscles: [], instructions: "Unterarme auf Bank abgestützt, Handgelenke beugen und strecken."),
        Exercise(id: "reverse-curl", name: "Reverse Curls", category: .strength, equipment: .barbell, primaryMuscles: [.forearms], secondaryMuscles: [.biceps], instructions: "Curl im Obergriff für Unterarm und Bizeps."),
        Exercise(id: "farmers-walk", name: "Farmers Walk", category: .strength, equipment: .dumbbell, primaryMuscles: [.forearms], secondaryMuscles: [.traps, .abs], instructions: "Schwere Kurzhanteln aufrecht gehend tragen."),

        // MARK: Bauch
        Exercise(id: "crunch", name: "Crunches", category: .strength, equipment: .bodyweight, primaryMuscles: [.abs], secondaryMuscles: [], instructions: "Oberkörper kontrolliert Richtung Knie aufrollen."),
        Exercise(id: "plank", name: "Plank", category: .strength, equipment: .bodyweight, primaryMuscles: [.abs], secondaryMuscles: [.lowerBack], instructions: "Körperspannung im Unterarmstütz halten."),
        Exercise(id: "hanging-leg-raise", name: "Beinheben hängend", category: .strength, equipment: .bodyweight, primaryMuscles: [.abs], secondaryMuscles: [.forearms], instructions: "An der Stange hängend die Beine kontrolliert anheben."),
        Exercise(id: "cable-crunch", name: "Cable Crunch", category: .strength, equipment: .cable, primaryMuscles: [.abs], secondaryMuscles: [], instructions: "Kniend am Kabelzug den Oberkörper einrollen."),
        Exercise(id: "ab-crunch-machine", name: "Crunch an der Maschine", category: .strength, equipment: .machine, primaryMuscles: [.abs], secondaryMuscles: [], instructions: "Oberkörper gegen den Widerstand einrollen, kontrolliert zurückführen."),
        Exercise(id: "russian-twist", name: "Russian Twists", category: .strength, equipment: .bodyweight, primaryMuscles: [.obliques], secondaryMuscles: [.abs], instructions: "Im Sitzen den Oberkörper mit Rotation von Seite zu Seite bewegen."),
        Exercise(id: "ab-wheel-rollout", name: "Ab Wheel Rollout", category: .strength, equipment: .none, primaryMuscles: [.abs], secondaryMuscles: [.lowerBack, .shoulders], instructions: "Mit dem Ab-Roller kontrolliert nach vorne rollen und zurückziehen."),
        Exercise(id: "mountain-climber", name: "Mountain Climbers", category: .cardio, equipment: .bodyweight, primaryMuscles: [.abs], secondaryMuscles: [.cardio], instructions: "Im Stütz die Knie abwechselnd zügig zur Brust ziehen."),
        Exercise(id: "sit-up", name: "Sit-ups", category: .strength, equipment: .bodyweight, primaryMuscles: [.abs], secondaryMuscles: [], instructions: "Kompletter Oberkörper-Aufrichter aus der Rückenlage."),

        // MARK: Seitliche Bauchmuskeln
        Exercise(id: "side-plank", name: "Side Plank", category: .strength, equipment: .bodyweight, primaryMuscles: [.obliques], secondaryMuscles: [.abs], instructions: "Seitlicher Unterarmstütz, Hüfte anheben und halten."),
        Exercise(id: "cable-woodchopper", name: "Woodchopper (Kabel)", category: .strength, equipment: .cable, primaryMuscles: [.obliques], secondaryMuscles: [.abs], instructions: "Diagonale Zugbewegung von oben nach unten über den Körper."),
        Exercise(id: "side-leg-raise", name: "Seitliches Beinheben", category: .strength, equipment: .bodyweight, primaryMuscles: [.obliques], secondaryMuscles: [.glutes], instructions: "Seitlich liegend das obere Bein kontrolliert anheben."),

        // MARK: Unterer Rücken
        Exercise(id: "good-morning", name: "Good Mornings", category: .strength, equipment: .barbell, primaryMuscles: [.lowerBack, .hamstrings], secondaryMuscles: [.glutes], instructions: "Langhantel im Nacken, Oberkörper aus der Hüfte nach vorne beugen."),
        Exercise(id: "bird-dog", name: "Bird Dog", category: .mobility, equipment: .bodyweight, primaryMuscles: [.lowerBack], secondaryMuscles: [.abs, .glutes], instructions: "Im Vierfüßlerstand gegengleich Arm und Bein ausstrecken."),

        // MARK: Gesäß
        Exercise(id: "hip-thrust", name: "Hip Thrust", category: .strength, equipment: .barbell, primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings], instructions: "Mit Schulterblättern auf der Bank die Hüfte nach oben drücken."),
        Exercise(id: "back-squat", name: "Kniebeuge (Langhantel)", category: .strength, equipment: .barbell, primaryMuscles: [.quads, .glutes], secondaryMuscles: [.hamstrings, .lowerBack], instructions: "Langhantel im Nacken, Hüfte tief unter die Kniehöhe absenken."),
        Exercise(id: "smith-machine-squat", name: "Kniebeuge (Smith Machine)", category: .strength, equipment: .machine, primaryMuscles: [.quads, .glutes], secondaryMuscles: [.hamstrings], instructions: "In der geführten Bahn die Hüfte tief unter die Kniehöhe absenken."),
        Exercise(id: "bulgarian-split-squat", name: "Bulgarian Split Squat", category: .strength, equipment: .dumbbell, primaryMuscles: [.quads, .glutes], secondaryMuscles: [.hamstrings], instructions: "Hinterer Fuß erhöht, vorderes Bein tief beugen."),
        Exercise(id: "glute-bridge", name: "Glute Bridge", category: .strength, equipment: .bodyweight, primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings], instructions: "Rückenlage, Hüfte anheben und Gesäß anspannen."),
        Exercise(id: "cable-glute-kickback", name: "Kickback (Kabel)", category: .strength, equipment: .cable, primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings], instructions: "Bein am Kabelzug nach hinten oben strecken."),
        Exercise(id: "sumo-deadlift", name: "Sumo-Kreuzheben", category: .strength, equipment: .barbell, primaryMuscles: [.glutes, .quads], secondaryMuscles: [.hamstrings, .lowerBack], instructions: "Breiter Stand, Langhantel mit geradem Rücken aufrichten."),

        // MARK: Quadrizeps
        Exercise(id: "leg-press", name: "Beinpresse", category: .strength, equipment: .machine, primaryMuscles: [.quads], secondaryMuscles: [.glutes], instructions: "Plattform aus tiefer Beugung nach oben drücken."),
        Exercise(id: "single-leg-press", name: "Beinpresse einbeinig", category: .strength, equipment: .machine, primaryMuscles: [.quads], secondaryMuscles: [.glutes], instructions: "Ein Bein isoliert aus tiefer Beugung nach oben drücken. Eingegebenes Gewicht gilt pro Seite.", isUnilateral: true),
        Exercise(id: "hack-squat", name: "Hackenschmidt-Kniebeuge", category: .strength, equipment: .machine, primaryMuscles: [.quads], secondaryMuscles: [.glutes, .hamstrings], instructions: "Rücken an der Schrägfläche, kontrolliert in die Hocke gehen und drücken."),
        Exercise(id: "walking-lunge", name: "Ausfallschritte", category: .strength, equipment: .dumbbell, primaryMuscles: [.quads, .glutes], secondaryMuscles: [.hamstrings], instructions: "Große Schritte nach vorne, hinteres Knie Richtung Boden senken."),
        Exercise(id: "leg-extension", name: "Beinstrecker", category: .strength, equipment: .machine, primaryMuscles: [.quads], secondaryMuscles: [], instructions: "Unterschenkel gegen den Widerstand strecken."),
        Exercise(id: "front-squat", name: "Front Squat", category: .strength, equipment: .barbell, primaryMuscles: [.quads], secondaryMuscles: [.glutes, .abs], instructions: "Langhantel frontal auf den Schultern, aufrecht in die Hocke gehen."),
        Exercise(id: "goblet-squat", name: "Goblet Squat", category: .strength, equipment: .dumbbell, primaryMuscles: [.quads, .glutes], secondaryMuscles: [], instructions: "Kurzhantel vor der Brust halten, tief in die Kniebeuge gehen."),

        // MARK: Beinbeuger
        Exercise(id: "romanian-deadlift", name: "Rumänisches Kreuzheben", category: .strength, equipment: .barbell, primaryMuscles: [.hamstrings], secondaryMuscles: [.glutes, .lowerBack], instructions: "Mit fast gestreckten Beinen die Hantel entlang der Beine absenken."),
        Exercise(id: "lying-leg-curl", name: "Beinbeuger liegend", category: .strength, equipment: .machine, primaryMuscles: [.hamstrings], secondaryMuscles: [], instructions: "Bauchlage, Fersen gegen den Widerstand zum Gesäß ziehen."),
        Exercise(id: "seated-leg-curl", name: "Beinbeuger sitzend", category: .strength, equipment: .machine, primaryMuscles: [.hamstrings], secondaryMuscles: [], instructions: "Im Sitzen die Unterschenkel gegen den Widerstand beugen."),
        Exercise(id: "nordic-curl", name: "Nordic Curls", category: .strength, equipment: .bodyweight, primaryMuscles: [.hamstrings], secondaryMuscles: [], instructions: "Knieend den Oberkörper exzentrisch kontrolliert nach vorne absenken."),

        // MARK: Waden
        Exercise(id: "standing-calf-raise", name: "Wadenheben stehend", category: .strength, equipment: .machine, primaryMuscles: [.calves], secondaryMuscles: [], instructions: "Fersen maximal anheben und kontrolliert absenken."),
        Exercise(id: "seated-calf-raise", name: "Wadenheben sitzend", category: .strength, equipment: .machine, primaryMuscles: [.calves], secondaryMuscles: [], instructions: "Im Sitzen die Fersen gegen den Widerstand anheben."),
        Exercise(id: "leg-press-calf-raise", name: "Wadenheben an der Beinpresse", category: .strength, equipment: .machine, primaryMuscles: [.calves], secondaryMuscles: [], instructions: "An der Beinpresse nur mit den Fußballen drücken."),

        // MARK: Nacken / Trapez
        Exercise(id: "barbell-shrug", name: "Shrugs (Langhantel)", category: .strength, equipment: .barbell, primaryMuscles: [.traps], secondaryMuscles: [.forearms], instructions: "Schultern gerade nach oben ziehen, kurz halten, senken."),
        Exercise(id: "dumbbell-shrug", name: "Shrugs (Kurzhantel)", category: .strength, equipment: .dumbbell, primaryMuscles: [.traps], secondaryMuscles: [.forearms], instructions: "Kurzhanteln seitlich haltend die Schultern hochziehen."),
        Exercise(id: "cable-shrug", name: "Shrugs am Kabelzug", category: .strength, equipment: .cable, primaryMuscles: [.traps], secondaryMuscles: [.forearms], instructions: "Am Kabelzug mit geradem Rücken die Schultern gerade nach oben ziehen, kurz halten, kontrolliert senken."),
        Exercise(id: "neck-flexion", name: "Nackenübung mit Band", category: .strength, equipment: .band, primaryMuscles: [.traps], secondaryMuscles: [], instructions: "Kopf gegen den Widerstand des Bandes langsam bewegen."),

        // MARK: Cardio
        Exercise(id: "running", name: "Laufen", category: .cardio, equipment: .none, primaryMuscles: [.cardio], secondaryMuscles: [.quads, .hamstrings, .calves], instructions: "Gleichmäßiges Lauftempo im Zielpulsbereich halten."),
        Exercise(id: "walking", name: "Gehen", category: .cardio, equipment: .none, primaryMuscles: [.cardio], secondaryMuscles: [.calves], instructions: "Zügiges, gleichmäßiges Gehtempo. Deutlich geringere Stoßbelastung für die Beine als Laufen."),
        Exercise(id: "cycling", name: "Radfahren", category: .cardio, equipment: .bike, primaryMuscles: [.cardio], secondaryMuscles: [.quads, .calves], instructions: "Konstante Trittfrequenz im Zielpulsbereich."),
        Exercise(id: "rowing-machine", name: "Rudergerät", category: .cardio, equipment: .machine, primaryMuscles: [.cardio], secondaryMuscles: [.upperBack, .quads], instructions: "Beine, Rücken und Arme im Rudertakt koordiniert einsetzen."),
        Exercise(id: "jump-rope", name: "Seilspringen", category: .cardio, equipment: .none, primaryMuscles: [.cardio], secondaryMuscles: [.calves], instructions: "Gleichmäßige, kurze Sprünge über das Seil."),
        Exercise(id: "stair-climber", name: "Stairmaster", category: .cardio, equipment: .machine, primaryMuscles: [.cardio], secondaryMuscles: [.glutes, .quads], instructions: "Kontinuierliches Treppensteigen im Zielpulsbereich."),
        Exercise(id: "swimming", name: "Schwimmen", category: .cardio, equipment: .none, primaryMuscles: [.cardio], secondaryMuscles: [.lats, .shoulders], instructions: "Gleichmäßige Zugbewegungen mit ruhiger Atmung."),
        Exercise(id: "sprint-intervals", name: "HIIT Sprints", category: .cardio, equipment: .none, primaryMuscles: [.cardio], secondaryMuscles: [.quads, .hamstrings], instructions: "Kurze maximale Sprints mit aktiven Pausen abwechseln."),
        Exercise(id: "elliptical", name: "Crosstrainer", category: .cardio, equipment: .machine, primaryMuscles: [.cardio], secondaryMuscles: [.quads, .glutes], instructions: "Gleichmäßige Bewegung ohne Gelenkbelastung im Zielpulsbereich."),

        // MARK: Mobilität
        Exercise(id: "foam-rolling", name: "Foam Rolling", category: .mobility, equipment: .none, primaryMuscles: [.quads], secondaryMuscles: [.hamstrings, .calves], instructions: "Muskulatur langsam über die Faszienrolle abrollen."),
        Exercise(id: "hip-opener", name: "Hüftöffner", category: .mobility, equipment: .none, primaryMuscles: [.glutes], secondaryMuscles: [.hamstrings], instructions: "Hüftgelenke in großer Range kreisen und dehnen."),
        Exercise(id: "shoulder-circles", name: "Schulterkreisen", category: .mobility, equipment: .none, primaryMuscles: [.shoulders], secondaryMuscles: [], instructions: "Schultern langsam in großen Kreisen bewegen."),
        Exercise(id: "cat-cow", name: "Katze-Kuh", category: .mobility, equipment: .none, primaryMuscles: [.lowerBack], secondaryMuscles: [.abs], instructions: "Wirbelsäule im Vierfüßlerstand abwechselnd runden und strecken."),
        Exercise(id: "yoga-flow", name: "Yoga Flow", category: .mobility, equipment: .none, primaryMuscles: [.abs], secondaryMuscles: [.shoulders, .hamstrings], instructions: "Fließende Abfolge aus Dehn- und Kräftigungspositionen."),
    ]

    public static let byId: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func exercises(for muscle: MuscleGroup) -> [Exercise] {
        all.filter { $0.primaryMuscles.contains(muscle) || $0.secondaryMuscles.contains(muscle) }
    }

    public static func exercises(in category: ExerciseCategory) -> [Exercise] {
        all.filter { $0.category == category }
    }
}
