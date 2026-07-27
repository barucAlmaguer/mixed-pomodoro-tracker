Feature: Mapa Fuerza de Papá integrado al tracker
  Scenario: Navegar entre las seis vistas del plan
    Given I open the Fuerza de Papá plan
    When I touch a tab for Hoy, Escalera, Metas, Ejercicios, Rutinas or Movilidad
    Then the selected view is shown and plan state is preserved

  Scenario: Registrar fuerza como hábito personal
    Given I select muscles trained today or yesterday
    When I save the session
    Then the activity is stored in the personal vault with its exercise tags

  Scenario: Registrar la carga ponderada de varios ejercicios
    Given I select several completed exercises for a strength session
    When I review their accumulated effort on the mannequin
    Then the heatmap shows the weighted muscle load and the session is stored with those muscles

  Scenario: Navegar y ampliar un entrenamiento de otro día
    Given I open the training recorder on today
    When I move to a previous day and save more than one training update
    Then its visible date changes and the day keeps one accumulated strength session

  Scenario: Mostrar la carga ya registrada del día seleccionado
    Given a strength session already exists for the selected day
    When I open its training recorder
    Then its completed exercises and accumulated mannequin heatmap are shown before I add more work

  Scenario: Consultar metas y ejercicios funcionales
    Given I am in Metas or Ejercicios
    When I open a card
    Then I see muscles, technique, video, and the functional relationship

  Scenario: Proyectar la carga de la semana
    Given I choose a weekly alternation and training days
    When I enable or disable a day
    Then load, heatmap, and series ranking recalculate

  Scenario: Elegir ejercicios según dolor o prioridad
    Given I mark muscles to avoid or prioritize
    When I consult exercises for today
    Then blocked exercises are excluded and matching ones are prioritized

  Scenario: Revisar historial muscular reciente
    Given sessions exist in the last seven days
    When I open Hoy
    Then I see the recency map and registered sessions

  Scenario: Filtrar y consultar drills de movilidad
    Given I am in Movilidad
    When I select a joint
    Then I only see pertinent drills by phase and their technique

  Scenario: Guardar chequeos funcionales
    Given I rate one or more functional tests
    When I save today's check
    Then the snapshot persists and shows progress from the previous one

  Scenario: Mantener una escalera de progresiones
    Given I open a movement pattern
    When I mark my current stage
    Then the stage persists and shows criteria, next step, and mobility gates

  Scenario: Inspeccionar anatomía y posturas del maniquí sin arrastrarlo
    Given I open the Fuerza de Papá plan
    When I show the mannequin and choose a camera shortcut or the Posturas muñeco tab
    Then I can access front, back, side, and posture diagnostic views

  Scenario: Editar y guardar una postura del maniquí por actividad
    Given I open the Posturas muñeco diagnostic view
    When I enter the pose editor, adjust a joint or camera, and save the posture
    Then its editable pose settings persist in the personal strength profile

  Scenario: Transformar el maniquí y asentarlo en el plano de gravedad
    Given I open the Posturas muñeco diagnostic view
    When I enter the editor and adjust global X, Y, Z and all three rotations
    Then I can use the plane, axes, and automatic ground contact controls

  Scenario: Manipular cadenas de brazos y piernas con joints intermedios
    Given I enter the pose editor
    When I select shoulders, elbows, wrists, hips, knees, or ankles
    Then the rig exposes axis-aware joint controls with separate upper and lower limb behavior

  Scenario: Ver la contribución muscular proporcional de cada ejercicio
    Given I open the Ejercicios view
    When I inspect an exercise mannequin
    Then its active muscles use the green, yellow, and red effort scale according to their relative contribution

  Scenario: Mostrar el origen efectivo de la postura del ejercicio
    Given I inspect an exercise without a specific saved pose
    When I save a specific pose for that exercise
    Then its mannequin footer changes from the shared preset label to the exercise-specific label

  Scenario: Visualizar props y postura específica de un ejercicio
    Given I open an exercise that uses weight or a support
    When I inspect its mannequin
    Then its visual pose and dumbbell or block props explain the exercise at a glance
