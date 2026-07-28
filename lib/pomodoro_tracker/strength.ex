defmodule PomodoroTracker.Strength do
  @moduledoc """
  The functional-strength plan and its vault-backed progress data.

  Sessions are concrete personal tasks tagged under `ejercicio>fuerza-papa` and
  completed on their recorded day. This deliberately makes the plan visible to
  the existing Habits surface instead of creating a second activity system.
  """

  alias PomodoroTracker.Vault

  @session_tag "ejercicio>fuerza-papa"
  @pose_joint_keys ~w(torso leftArm rightArm leftElbow rightElbow leftLeg rightLeg leftKnee rightKnee)

  @muscles %{
    "grip" => "Agarre y antebrazos",
    "traps" => "Trapecio",
    "upperback" => "Espalda alta (romboides)",
    "shoulders" => "Hombros",
    "chest" => "Pecho",
    "arms" => "Brazos",
    "core" => "Core anti-flexión",
    "obliques" => "Oblicuos (core lateral)",
    "glutes" => "Glúteos",
    "hams" => "Isquios",
    "quads" => "Cuádriceps",
    "erectors" => "Erectores de columna"
  }

  @exercises [
    %{
      id: "farmer",
      name: "Farmer carry (2 manos)",
      routine: "A",
      muscles: ["grip", "traps", "core", "erectors"],
      effort: %{"grip" => 1.0, "traps" => 0.75, "core" => 0.6, "erectors" => 0.55},
      sets: "3×30–40 pasos",
      note: "Caminar cargando peso: la base de toda carga en la vida real.",
      how: [
        "Mancuerna en cada mano",
        "pecho erguido y hombros atrás",
        "pasos cortos sin ladearte"
      ]
    },
    %{
      id: "suitcase",
      name: "Suitcase carry (1 mano)",
      routine: "B",
      new: true,
      muscles: ["obliques", "grip", "traps", "core"],
      effort: %{"obliques" => 1.0, "grip" => 0.85, "traps" => 0.6, "core" => 0.75},
      sets: "3×30 pasos /lado",
      note: "Cargar de un solo lado sin ladearte: bebé o garrafón.",
      how: ["Una mancuerna a un costado", "camina recto", "el core resiste la caída lateral"]
    },
    %{
      id: "rdl",
      name: "Peso muerto rumano",
      routine: "B",
      muscles: ["hams", "glutes", "erectors", "grip"],
      effort: %{"hams" => 1.0, "glutes" => 0.85, "erectors" => 0.65, "grip" => 0.45},
      sets: "3×10–12",
      note: "Enseña a levantar del piso con cadera, no con espalda.",
      how: [
        "Mancuernas frente a los muslos",
        "cadera atrás y rodillas suaves",
        "sube apretando glúteos"
      ]
    },
    %{
      id: "goblet",
      name: "Goblet squat",
      routine: "A",
      muscles: ["quads", "glutes", "core", "grip"],
      effort: %{"quads" => 1.0, "glutes" => 0.65, "core" => 0.5, "grip" => 0.35},
      sets: "3×10–15",
      note: "Patrón de agacharse con carga al frente.",
      how: ["Mancuerna al pecho", "talones plantados", "pecho erguido"]
    },
    %{
      id: "bulgarian",
      name: "Sentadilla búlgara / zancadas",
      routine: "B",
      muscles: ["quads", "glutes", "core"],
      effort: %{"quads" => 1.0, "glutes" => 0.8, "core" => 0.45},
      sets: "3×8–10 /pierna",
      note: "Fuerza de una sola pierna para levantarte del piso.",
      how: ["Empeine trasero en silla", "baja vertical", "sube con el talón"]
    },
    %{
      id: "row",
      name: "Remo a una mano",
      routine: "A",
      muscles: ["upperback", "traps", "arms", "grip"],
      effort: %{"upperback" => 1.0, "traps" => 0.7, "arms" => 0.65, "grip" => 0.45},
      sets: "3×10–12 /lado",
      note: "Espalda fuerte que sostiene la postura.",
      how: ["Apóyate en banco o silla", "jala hacia la cadera", "baja controlado"]
    },
    %{
      id: "pullapart",
      name: "Band pull-apart",
      routine: "A",
      new: true,
      muscles: ["upperback", "traps", "shoulders"],
      effort: %{"upperback" => 1.0, "traps" => 0.7, "shoulders" => 0.65},
      sets: "3×15–20",
      note: "Resistencia postural: antídoto al escritorio.",
      how: ["Banda al frente", "sepárala hasta el pecho", "junta omóplatos"]
    },
    %{
      id: "ohp",
      name: "Press de hombro",
      routine: "B",
      muscles: ["shoulders", "arms", "core"],
      effort: %{"shoulders" => 1.0, "arms" => 0.75, "core" => 0.45},
      sets: "3×8–12",
      note: "Llevar peso arriba con control.",
      how: ["Mancuernas a los hombros", "empuja vertical", "core apretado"]
    },
    %{
      id: "cleanpress",
      name: "Curl + press",
      routine: "B",
      muscles: ["arms", "shoulders", "core", "grip"],
      effort: %{"arms" => 0.95, "shoulders" => 1.0, "core" => 0.5, "grip" => 0.65},
      sets: "3×8",
      note: "Del piso al hombro en un movimiento.",
      how: ["Curl de bíceps", "press arriba sin pausa", "baja en dos tiempos"]
    },
    %{
      id: "pushup",
      name: "Lagartijas en mancuernas",
      routine: "A",
      muscles: ["chest", "arms", "shoulders", "core"],
      effort: %{"chest" => 1.0, "arms" => 0.85, "shoulders" => 0.7, "core" => 0.45},
      sets: "3× al fallo −2",
      note: "Empujar tu cuerpo: piso y juego.",
      how: ["Muñecas neutras", "cuerpo en línea", "pecho entre las manos"]
    },
    %{
      id: "deadbug",
      name: "Dead bug",
      routine: "B",
      muscles: ["core"],
      effort: %{"core" => 1.0},
      sets: "3×8 /lado",
      note: "Core estable sin molestar la espalda baja.",
      how: ["Boca arriba a 90°", "extiende brazo y pierna opuestos", "espalda baja pegada"]
    },
    %{
      id: "plank",
      name: "Plancha + plancha lateral",
      routine: "A",
      muscles: ["core", "obliques", "shoulders"],
      effort: %{"core" => 0.9, "obliques" => 0.75, "shoulders" => 0.5},
      sets: "3×20–40 s",
      note: "La base para cargar durante mucho tiempo.",
      how: ["Antebrazos al piso", "cuerpo en línea", "aprieta abdomen y glúteos"]
    },
    %{
      id: "floorpress",
      name: "Press de piso",
      routine: "X",
      substitute: "pushup",
      muscles: ["chest", "arms", "shoulders"],
      effort: %{"chest" => 1.0, "arms" => 0.85, "shoulders" => 0.55},
      sets: "3×8–12",
      note: "Pecho con rango amable para el hombro.",
      how: ["Acostado", "codos a 45°", "baja hasta el piso"]
    },
    %{
      id: "lateralraise",
      name: "Elevaciones laterales",
      routine: "X",
      substitute: "ohp",
      muscles: ["shoulders"],
      effort: %{"shoulders" => 1.0},
      sets: "3×12–15",
      note: "Hombro aislado con poco peso.",
      how: ["Mancuernas a los costados", "sube a la horizontal", "baja lento"]
    },
    %{
      id: "bandrow",
      name: "Remo con banda sentado",
      routine: "X",
      substitute: "row",
      muscles: ["upperback", "traps", "arms"],
      effort: %{"upperback" => 1.0, "traps" => 0.7, "arms" => 0.6},
      sets: "3×12–15",
      note: "Espalda alta sin cargar la lumbar.",
      how: ["Banda en los pies", "jala al abdomen", "pausa omóplatos"]
    },
    %{
      id: "facepull",
      name: "Face pull con banda",
      routine: "X",
      substitute: "pullapart",
      muscles: ["upperback", "shoulders", "traps"],
      effort: %{"upperback" => 0.9, "shoulders" => 1.0, "traps" => 0.7},
      sets: "3×15",
      note: "El amigo de la postura de oficina.",
      how: ["Banda a la cara", "jala abriendo codos", "pausa atrás"]
    },
    %{
      id: "reversefly",
      name: "Vuelo posterior",
      routine: "X",
      substitute: "pullapart",
      muscles: ["upperback", "shoulders"],
      effort: %{"upperback" => 0.8, "shoulders" => 1.0},
      sets: "3×12–15",
      note: "Deltoide posterior con mancuernas ligeras.",
      how: ["Inclínate recto", "abre como alas", "baja controlado"]
    },
    %{
      id: "shrug",
      name: "Encogimientos (shrugs)",
      routine: "X",
      substitute: "farmer",
      muscles: ["traps", "grip"],
      effort: %{"traps" => 1.0, "grip" => 0.45},
      sets: "3×12–15",
      note: "Trapecio para que el hombro no cuelgue al cargar.",
      how: ["Mancuernas a los costados", "sube hombros", "baja lento"]
    },
    %{
      id: "hammercurl",
      name: "Curl martillo",
      routine: "X",
      substitute: "cleanpress",
      muscles: ["arms", "grip"],
      effort: %{"arms" => 1.0, "grip" => 0.65},
      sets: "3×10–12",
      note: "Bíceps y antebrazo: agarre funcional.",
      how: ["Palmas enfrentadas", "sube sin balanceo", "baja en 2–3 s"]
    },
    %{
      id: "waiter",
      name: "Waiter carry",
      routine: "X",
      substitute: "farmer",
      muscles: ["shoulders", "core", "grip"],
      effort: %{"shoulders" => 1.0, "core" => 0.7, "grip" => 0.65},
      sets: "3×20 pasos /lado",
      note: "Estabilidad de hombro cargando arriba.",
      how: ["Brazo extendido", "camina recto", "cambia lado"]
    },
    %{
      id: "stepup",
      name: "Step-up",
      routine: "X",
      substitute: "bulgarian",
      muscles: ["quads", "glutes", "core"],
      effort: %{"quads" => 1.0, "glutes" => 0.75, "core" => 0.4},
      sets: "3×8–10 /pierna",
      note: "Subir a un banco, amable con rodillas.",
      how: ["Pie completo al banco", "empuja talón", "baja controlado"]
    },
    %{
      id: "bridge",
      name: "Puente de glúteo",
      routine: "X",
      substitute: "rdl",
      muscles: ["glutes", "hams", "core"],
      effort: %{"glutes" => 1.0, "hams" => 0.65, "core" => 0.35},
      sets: "3×12–15",
      note: "Glúteos sin cargar la espalda.",
      how: ["Boca arriba", "sube cadera", "pausa 2 s"]
    },
    %{
      id: "pallof",
      name: "Pallof press con banda",
      routine: "X",
      substitute: "deadbug",
      muscles: ["obliques", "core"],
      effort: %{"obliques" => 1.0, "core" => 0.85},
      sets: "3×10 /lado",
      note: "Anti-rotación para no ladearte.",
      how: ["Banda al costado", "extiende brazos", "resiste sin girar"]
    },
    %{
      id: "birddog",
      name: "Bird dog",
      routine: "X",
      substitute: "plank",
      muscles: ["core", "erectors", "glutes"],
      effort: %{"core" => 0.85, "erectors" => 0.8, "glutes" => 0.65},
      sets: "3×8 /lado",
      note: "Espalda baja fuerte y segura.",
      how: ["Cuatro puntos", "extiende opuestos", "cadera nivelada"]
    }
  ]

  @functions [
    %{
      id: "jug",
      tag: "F1",
      title: "Cargar el garrafón",
      now: "Batallas para cargar uno",
      goal: "Dos a la vez o uno al hombro",
      muscles: ["grip", "traps", "glutes", "hams", "core", "erectors"],
      exercises: ["farmer", "suitcase", "rdl", "cleanpress", "row"],
      why: "Cargar ~20 kg es agarre, cadera y torso que no se dobla."
    },
    %{
      id: "pour",
      tag: "F2",
      title: "Servir agua del garrafón con control",
      now: "Cuesta llenar botes chicos",
      goal: "Verter estable, sin temblar",
      muscles: ["shoulders", "grip", "obliques", "core"],
      exercises: ["ohp", "cleanpress", "suitcase", "deadbug"],
      why: "Sostener peso lejos del cuerpo es hombro y core lateral."
    },
    %{
      id: "floor",
      tag: "F3",
      title: "Levantarte del piso",
      now: "Cuesta trabajo, truena todo",
      goal: "Casi con una pierna, sin manos",
      muscles: ["quads", "glutes", "core"],
      exercises: ["bulgarian", "goblet", "pushup"],
      why: "Levantarse del piso es pierna unilateral y empuje."
    },
    %{
      id: "desk",
      tag: "F4",
      title: "Espalda alta para la compu",
      now: "Duele sin silla ergonómica",
      goal: "Postura que se sostiene sola",
      muscles: ["upperback", "traps", "erectors"],
      exercises: ["pullapart", "row", "farmer"],
      why: "La espalda alta necesita resistencia, no solo estiramiento."
    },
    %{
      id: "play",
      tag: "F5",
      title: "Jugar con un niño",
      now: "Poca capacidad de trabajo",
      goal: "Aguantar el juego más que el niño",
      muscles: ["quads", "glutes", "core", "shoulders"],
      exercises: ["bulgarian", "goblet", "farmer", "cleanpress", "pushup"],
      why: "Combina carga, sentadilla y capacidad de repetir."
    },
    %{
      id: "baby",
      tag: "F6",
      title: "Cargar un bebé con un brazo",
      now: "—",
      goal: "30+ min sin ladearte",
      muscles: ["obliques", "grip", "traps", "arms"],
      exercises: ["suitcase", "cleanpress", "plank"],
      why: "Carga asimétrica sostenida: oblicuos, agarre y brazo."
    }
  ]

  @joints %{
    "ankle" => "Tobillos",
    "hip" => "Cadera",
    "tspine" => "Columna torácica",
    "shoulder" => "Hombros",
    "wrist" => "Muñecas"
  }
  @drills [
    %{
      id: "wgs",
      name: "El mejor estiramiento del mundo",
      phase: "warm",
      joints: ["hip", "tspine", "ankle"],
      dose: "2×5 /lado",
      how: ["Zancada profunda", "codo interno al piso", "gira al cielo"]
    },
    %{
      id: "catcow",
      name: "Gato-vaca",
      phase: "warm",
      joints: ["tspine", "hip"],
      dose: "2×8",
      how: ["Cuatro puntos", "arquea y redondea", "sigue respiración"]
    },
    %{
      id: "legswing",
      name: "Balanceos de pierna",
      phase: "warm",
      joints: ["hip"],
      dose: "2×10 /lado",
      how: ["Apóyate", "balancea al frente y atrás", "amplitud gradual"]
    },
    %{
      id: "anklerock",
      name: "Rocks de tobillo",
      phase: "warm",
      joints: ["ankle"],
      dose: "2×10 /lado",
      how: ["Rodilla adelante", "talón plantado", "antes de sentadillas"]
    },
    %{
      id: "armwrist",
      name: "Círculos de brazos y muñecas",
      phase: "warm",
      joints: ["shoulder", "wrist"],
      dose: "10 c/dirección",
      how: ["Círculos amplios", "muñecas suaves", "antes de lagartijas"]
    },
    %{
      id: "hipflexor",
      name: "Flexor de cadera",
      phase: "cool",
      joints: ["hip"],
      dose: "2×30 s /lado",
      how: ["Media rodilla", "glúteo apretado", "sin arquear"]
    },
    %{
      id: "fig4",
      name: "Figura 4 acostado",
      phase: "cool",
      joints: ["hip"],
      dose: "2×30 s /lado",
      how: ["Boca arriba", "tobillo en rodilla", "jala muslo"]
    },
    %{
      id: "doorpec",
      name: "Pecho en marco de puerta",
      phase: "cool",
      joints: ["shoulder"],
      dose: "2×30 s",
      how: ["Antebrazo en marco", "codo a 90°", "gira torso"]
    },
    %{
      id: "hamstring",
      name: "Isquios con toalla",
      phase: "cool",
      joints: ["hip"],
      dose: "2×30 s /lado",
      how: ["Boca arriba", "toalla en planta", "sin rebotar"]
    },
    %{
      id: "childreach",
      name: "Postura del niño + alcance",
      phase: "cool",
      joints: ["tspine", "shoulder"],
      dose: "45 s",
      how: ["Talones", "brazos largos", "camina manos"]
    },
    %{
      id: "chairext",
      name: "Extensión torácica en silla",
      phase: "snack",
      joints: ["tspine"],
      dose: "×8 · cada 2 h",
      how: ["Manos nuca", "abre respaldo", "exhala"]
    },
    %{
      id: "standhinge",
      name: "Bisagra + apertura",
      phase: "snack",
      joints: ["hip", "shoulder"],
      dose: "×8",
      how: ["Bisagra recta", "sube", "abre pecho"]
    },
    %{
      id: "wristflow",
      name: "Flujo de muñecas",
      phase: "snack",
      joints: ["wrist"],
      dose: "×10 c/dirección",
      how: ["Palmas juntas", "círculos suaves", "flexión y extensión"]
    },
    %{
      id: "deepsquat",
      name: "Cuclilla profunda sostenida",
      phase: "snack",
      joints: ["ankle", "hip"],
      dose: "Acumula 60 s",
      how: ["Talones al piso", "usa marco si hace falta", "test y drill"]
    }
  ]
  @tests [
    %{
      id: "sitrise",
      name: "Levantarte del piso sin manos",
      levels: ["Con manos", "Con 1 apoyo", "Sin apoyos"],
      link: "F3"
    },
    %{
      id: "squathold",
      name: "Cuclilla profunda, talones al piso",
      levels: ["No llego", "< 30 s", "60 s +"],
      link: "Tobillo · cadera"
    },
    %{
      id: "toetouch",
      name: "Tocar el piso, piernas rectas",
      levels: ["Lejos", "Con dedos", "Palmas"],
      link: "Cadera"
    },
    %{
      id: "apley",
      name: "Manos juntas tras la espalda",
      levels: ["Lejos", "Se tocan", "Agarre"],
      link: "Hombros"
    },
    %{
      id: "carry40",
      name: "Farmer carry 40 pasos · 10 kg/mano",
      levels: ["No puedo", "Con pausas", "Fluido"],
      link: "F1"
    }
  ]

  def patterns do
    [
      %{
        id: "squat",
        name: "Sentadilla",
        summit: "Pistol squat",
        stages: [
          stage("Asistida", "3×12 profundas"),
          stage("Libre completa", "3×15 hasta abajo"),
          stage("Goblet", "3×12 con 10 kg"),
          stage("Búlgara", "3×10 por pierna"),
          stage("Step-down lento", "3×8 por pierna"),
          stage(
            "Pistol asistido",
            "3×5 por pierna",
            {"squathold", 1, "Cuclilla profunda ≥ 30 s", ["anklerock", "deepsquat"]}
          ),
          stage(
            "Pistol a banco",
            "3×5 por pierna",
            {"toetouch", 1, "Tocar el piso con los dedos", ["hamstring"]}
          ),
          stage(
            "Pistol completo",
            "La cima 🏔",
            {"squathold", 2, "Cuclilla profunda 60 s", ["deepsquat"]}
          )
        ]
      },
      %{
        id: "push",
        name: "Empuje",
        summit: "Lagartija arquera",
        stages: [
          stage("Lagartija a pared", "3×12 fáciles"),
          stage("Inclinada", "3×10"),
          stage("Con rodillas", "3×12 rectas"),
          stage("Completa", "3×8"),
          stage("Pies elevados", "3×8"),
          stage("Arquera", "3×5 por lado")
        ]
      },
      %{
        id: "hinge",
        name: "Bisagra",
        summit: "RDL a 1 pierna",
        stages: [
          stage("Puente de glúteo", "3×15"),
          stage("Puente a 1 pierna", "3×10 por lado"),
          stage("RDL con mancuernas", "3×12"),
          stage("RDL b-stance", "3×8 por lado"),
          stage(
            "RDL a 1 pierna",
            "3×8 sin perder equilibrio",
            {"toetouch", 1, "Tocar el piso con los dedos", ["hamstring"]}
          )
        ]
      },
      %{
        id: "pull",
        name: "Jalón",
        summit: "Remo invertido elevado",
        stages: [
          stage("Band pull-apart", "3×20"),
          stage("Remo con banda", "3×15"),
          stage("Remo con mancuerna", "3×12 por lado"),
          stage("Remo bajo mesa", "3×8"),
          stage("Remo invertido elevado", "3×8")
        ]
      },
      %{
        id: "carry",
        name: "Carga",
        summit: "2 garrafones 🏆 (F1)",
        stages: [
          stage("Farmer 2×10 kg", "40 pasos"),
          stage("Suitcase 10 kg", "40 pasos/lado"),
          stage(
            "Waiter carry",
            "20 pasos/lado",
            {"apley", 1, "Dedos se tocan tras la espalda", ["doorpec", "childreach"]}
          ),
          stage("Clean al hombro", "3×5 por lado"),
          stage("1 garrafón al hombro", "Controlado"),
          stage("2 garrafones", "Meta F1 completa 🏆")
        ]
      },
      %{
        id: "core",
        name: "Core",
        summit: "Plancha + toque de hombro",
        stages: [
          stage("Plancha con rodillas", "3×30 s"),
          stage("Plancha completa", "3×40 s"),
          stage("Plancha lateral", "30 s por lado"),
          stage("Pallof press", "3×10 por lado"),
          stage("Plancha + toque", "3×10 sin mover cadera")
        ]
      }
    ]
  end

  defp stage(name, unlock, gate \\ nil), do: %{name: name, unlock: unlock, gate: gate}

  def muscles, do: @muscles
  def exercises, do: @exercises
  def functions, do: @functions
  def joints, do: @joints
  def drills, do: @drills
  def tests, do: @tests

  def list_sessions do
    Vault.list_tasks(:personal, :backlog)
    |> Enum.filter(&(get_in(&1, [:frontmatter, "strength_session"]) == true))
    |> Enum.map(fn task ->
      %{
        id: task.id,
        date: task.frontmatter["session_date"],
        muscles: task.frontmatter["strength_muscles"] || [],
        exercises: task.frontmatter["strength_exercises"] || []
      }
    end)
    |> Enum.filter(&is_binary(&1.date))
    |> Enum.sort_by(& &1.date, :desc)
  end

  def save_session(%Date{} = date, muscles, exercises \\ []) do
    muscles = Enum.filter(Enum.uniq(muscles), &Map.has_key?(@muscles, &1))
    exercise_ids = MapSet.new(Enum.map(@exercises, & &1.id))
    exercises = Enum.filter(Enum.uniq(exercises), &MapSet.member?(exercise_ids, &1))
    id = "fuerza-papa-" <> (date |> Date.to_iso8601() |> String.replace("-", ""))
    existing = Enum.find(Vault.list_tasks(:personal, :backlog), &(&1.id == id))
    merged = Enum.uniq(((existing && existing.frontmatter["strength_muscles"]) || []) ++ muscles)

    merged_exercises =
      Enum.uniq(((existing && existing.frontmatter["strength_exercises"]) || []) ++ exercises)

    tags = [@session_tag | Enum.map(merged, &"#{@session_tag}>#{&1}")]

    result =
      if existing do
        Vault.update_task(existing.path, %{
          tags: tags,
          strength_muscles: merged,
          strength_exercises: merged_exercises,
          strength_session: true,
          session_date: Date.to_iso8601(date)
        })
      else
        Vault.create_task(:personal, :backlog, %{
          id: id,
          title: "Entrenamiento funcional · #{Date.to_iso8601(date)}",
          tags: tags,
          strength_session: true,
          strength_muscles: merged,
          strength_exercises: merged_exercises,
          session_date: Date.to_iso8601(date),
          created_at: Date.to_iso8601(date),
          body: "Entrenamiento registrado desde Fuerza funcional."
        })
      end

    with :ok <- normalize_write(result),
         {:ok, day} <- Vault.load_day(date),
         {:ok, _} <- Vault.save_day(%{day | done: Enum.uniq(day.done ++ [id])}) do
      {:ok, id}
    end
  end

  def delete_session(id) do
    case Enum.find(
           Vault.list_tasks(:personal, :backlog),
           &(&1.id == id and get_in(&1, [:frontmatter, "strength_session"]) == true)
         ) do
      nil ->
        {:error, :not_found}

      task ->
        with {:ok, date} <- Date.from_iso8601(task.frontmatter["session_date"]),
             :ok <- Vault.delete_task(task.path),
             {:ok, day} <- Vault.load_day(date),
             {:ok, _} <- Vault.save_day(%{day | done: List.delete(day.done, id)}) do
          :ok
        end
    end
  end

  def profile do
    profile =
      Vault.read_setting(:personal, "fuerza-papa", %{
        "tests" => %{},
        "levels" => %{},
        "poses" => %{}
      })

    snapshots =
      case profile["tests"] do
        tests when is_map(tests) ->
          tests
          |> Enum.map(fn {date, results} -> %{"date" => date, "results" => results} end)
          |> Enum.sort_by(& &1["date"], :desc)

        tests when is_list(tests) ->
          tests

        _ ->
          []
      end

    Map.put(profile, "tests", snapshots)
  end

  def save_tests(results) do
    profile = profile()
    today = Date.utc_today() |> Date.to_iso8601()
    snapshot = %{"date" => today, "results" => results}
    snapshots = [snapshot | Enum.reject(profile["tests"] || [], &(&1["date"] == today))]

    Vault.write_setting(
      :personal,
      "fuerza-papa",
      profile_for_storage(Map.put(profile, "tests", snapshots))
    )
  end

  def save_level(pattern_id, stage) do
    profile = profile()
    levels = Map.put(profile["levels"] || %{}, pattern_id, stage)

    Vault.write_setting(
      :personal,
      "fuerza-papa",
      profile |> Map.put("levels", levels) |> profile_for_storage()
    )
  end

  def save_pose(pose_key, settings) when is_binary(pose_key) and is_map(settings) do
    if String.match?(pose_key, ~r/^[a-z0-9_-]{1,80}$/) do
      profile = profile()
      poses = Map.put(profile["poses"] || %{}, pose_key, normalize_pose_settings(settings))

      Vault.write_setting(
        :personal,
        "fuerza-papa",
        profile |> Map.put("poses", poses) |> profile_for_storage()
      )
      |> normalize_write()
    else
      {:error, :invalid_pose_key}
    end
  end

  defp normalize_pose_settings(settings) do
    joints =
      settings
      |> Map.get("joints", %{})
      |> Map.take(@pose_joint_keys)
      |> Map.new(fn {key, value} -> {key, normalize_joint(value)} end)

    transform = Map.get(settings, "transform", %{})
    camera = Map.get(settings, "camera", %{})

    %{
      "joints" => joints,
      "transform" => %{
        "x" => bounded_number(transform["x"], 0.0, -3.0, 3.0),
        "y" => bounded_number(transform["y"], 0.0, -3.0, 3.0),
        "z" => bounded_number(transform["z"], 0.0, -3.0, 3.0),
        "rotationX" => bounded_number(transform["rotationX"], 0.0, -3.14, 3.14),
        "rotationY" =>
          bounded_number(transform["rotationY"] || transform["yaw"], 0.0, -3.14, 3.14),
        "rotationZ" => bounded_number(transform["rotationZ"], 0.0, -3.14, 3.14)
      },
      "camera" => %{
        "position" => bounded_vector(camera["position"], [0.0, -0.15, 9.0], -15.0, 15.0),
        "target" => bounded_vector(camera["target"], [0.0, -0.35, 0.0], -5.0, 5.0)
      }
    }
  end

  defp bounded_vector(values, _fallback, min, max) when is_list(values) and length(values) == 3,
    do: Enum.map(values, &bounded_number(&1, 0.0, min, max))

  defp bounded_vector(_, fallback, _, _), do: fallback

  defp normalize_joint(value) when is_number(value),
    do: %{"x" => bounded_number(value, 0.0, -3.14, 3.14), "y" => 0.0, "z" => 0.0}

  defp normalize_joint(value) when is_map(value) do
    %{
      "x" => bounded_number(value["x"], 0.0, -3.14, 3.14),
      "y" => bounded_number(value["y"], 0.0, -3.14, 3.14),
      "z" => bounded_number(value["z"], 0.0, -3.14, 3.14)
    }
  end

  defp normalize_joint(_), do: %{"x" => 0.0, "y" => 0.0, "z" => 0.0}

  defp bounded_number(value, _fallback, min, max) when is_number(value),
    do: value |> max(min) |> min(max)

  defp bounded_number(_, fallback, _, _), do: fallback

  defp normalize_write({:ok, _}), do: :ok
  defp normalize_write(:ok), do: :ok
  defp normalize_write(error), do: error

  defp profile_for_storage(profile) do
    Map.update(profile, "tests", %{}, fn snapshots ->
      if is_list(snapshots), do: Map.new(snapshots, &{&1["date"], &1["results"]}), else: snapshots
    end)
  end
end
