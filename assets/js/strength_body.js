import * as THREE from "three"
import {OrbitControls} from "three/addons/controls/OrbitControls.js"

const palette = {
  surface: 0x07111c,
  line: 0x557086,
  cyan: 0x38bdf8,
  slate: 0x506579,
}

const parse = (value, fallback) => {
  try {
    return JSON.parse(value || "")
  } catch (_) {
    return fallback
  }
}

const heat = (level) => {
  if (!level || level <= 0) return "#506579"
  if (level < 0.5) return "#33a05f"
  if (level < 0.8) return "#e9b41f"
  return "#d6402c"
}

const poseFor = (name) => ({
  neutral: {torso: 0, leftArm: 0, rightArm: 0, leftLeg: 0, rightLeg: 0},
  carry: {torso: -0.08, leftArm: 0.12, rightArm: -0.12, leftLeg: 0.04, rightLeg: -0.04},
  squat: {torso: 0.28, leftArm: -0.5, rightArm: -0.5, leftLeg: 0.72, rightLeg: 0.72},
  hinge: {torso: 0.72, leftArm: 0.18, rightArm: 0.18, leftLeg: 0.32, rightLeg: 0.32},
  press: {torso: -0.08, leftArm: -2.48, rightArm: -2.48, leftLeg: 0, rightLeg: 0},
  pushup: {torso: 1.42, leftArm: -0.72, rightArm: -0.72, leftLeg: -0.18, rightLeg: -0.18},
  mobility: {torso: 0.22, leftArm: -0.85, rightArm: -0.18, leftLeg: 0.12, rightLeg: -0.25},
  goblet: {torso: 0.28, leftArm: -0.5, rightArm: -0.5, leftLeg: 0.72, rightLeg: 0.72},
  farmer: {torso: -0.08, leftArm: 0.12, rightArm: -0.12, leftLeg: 0.04, rightLeg: -0.04},
  suitcase: {torso: -0.06, leftArm: 0.08, rightArm: -0.18, leftLeg: 0.06, rightLeg: -0.04},
  rdl: {torso: 0.72, leftArm: 0.18, rightArm: 0.18, leftLeg: 0.32, rightLeg: 0.32},
  bulgarian: {torso: 0.32, leftArm: -0.16, rightArm: -0.16, leftLeg: 0.78, rightLeg: -0.54, leftKnee: 0.55, rightKnee: 0.92},
  row: {torso: 0.62, leftArm: 0.24, rightArm: -0.92, rightElbow: 0.96, leftLeg: 0.2, rightLeg: 0.2},
  pullapart: {torso: -0.04, leftArm: {z: -1.42}, rightArm: {z: 1.42}, leftElbow: -0.16, rightElbow: -0.16},
  ohp: {torso: -0.08, leftArm: -2.48, rightArm: -2.48, leftLeg: 0, rightLeg: 0},
  cleanpress: {torso: -0.04, leftArm: -2.32, rightArm: -2.32, leftElbow: 0.18, rightElbow: 0.18},
  deadbug: {torso: 1.55, leftArm: -1.65, rightArm: -0.16, leftLeg: 1.2, rightLeg: -0.46, leftKnee: -0.62, rightKnee: 0.48},
  plank: {torso: 1.42, leftArm: -0.9, rightArm: -0.9, leftElbow: 0.3, rightElbow: 0.3, leftLeg: -0.18, rightLeg: -0.18},
  floorpress: {torso: 1.42, leftArm: -1.85, rightArm: -1.85, leftLeg: -0.18, rightLeg: -0.18},
  lateralraise: {torso: -0.04, leftArm: {z: -1.34}, rightArm: {z: 1.34}},
  bandrow: {torso: 0.48, leftArm: -0.72, rightArm: -0.72, leftElbow: 0.78, rightElbow: 0.78, leftLeg: 1.18, rightLeg: 1.18},
  facepull: {torso: -0.02, leftArm: -1.14, rightArm: -1.14, leftElbow: 1.38, rightElbow: 1.38},
  reversefly: {torso: 0.74, leftArm: {z: -1.08}, rightArm: {z: 1.08}, leftLeg: 0.25, rightLeg: 0.25},
  shrug: {torso: -0.08, leftArm: 0.12, rightArm: -0.12},
  hammercurl: {torso: -0.04, leftArm: -0.14, rightArm: -0.14, leftElbow: -1.18, rightElbow: -1.18},
  waiter: {torso: -0.06, leftArm: 0.1, rightArm: -2.5, rightElbow: 0.08},
  stepup: {torso: 0.16, leftArm: 0.08, rightArm: -0.08, leftLeg: 0.68, rightLeg: -0.3, leftKnee: 0.46, rightKnee: 0.22},
  bridge: {torso: 1.42, leftArm: 0.2, rightArm: -0.2, leftLeg: 1.02, rightLeg: 1.02, leftKnee: -0.98, rightKnee: -0.98},
  pallof: {torso: -0.04, leftArm: -1.1, rightArm: -1.1, leftElbow: 0.58, rightElbow: 0.58},
  birddog: {torso: 1.42, leftArm: -1.25, rightArm: 0.3, leftLeg: 0.82, rightLeg: -0.72, leftKnee: -0.38, rightKnee: 0.24},
}[name] || poseFor("neutral"))

const jointKeys = ["torso", "leftArm", "rightArm", "leftElbow", "rightElbow", "leftLeg", "rightLeg", "leftKnee", "rightKnee"]
const rotation = (value = {}) => typeof value === "number"
  ? {x: value, y: 0, z: 0}
  : {x: Number(value.x) || 0, y: Number(value.y) || 0, z: Number(value.z) || 0}

const targetsFor = (pose, overrides = {}) => Object.fromEntries(jointKeys.map((key) => {
  const offset = rotation(overrides[key])
  return [key, {x: (pose[key] || 0) + offset.x, y: offset.y, z: offset.z}]
}))

const polygon = (points) => {
  const shape = new THREE.Shape()
  shape.moveTo(...points[0])
  points.slice(1).forEach((point) => shape.lineTo(...point))
  shape.closePath()
  return new THREE.ShapeGeometry(shape)
}

const trapezoid = (top, bottom, height) => polygon([
  [-top / 2, height / 2], [top / 2, height / 2], [bottom / 2, -height / 2], [-bottom / 2, -height / 2],
])

export const StrengthBody = {
  mounted() {
    this.mountScene()
    this.sync()
  },

  updated() {
    this.sync()
  },

  destroyed() {
    cancelAnimationFrame(this.animationFrame)
    this.controls?.dispose()
    this.renderer?.dispose()
    this.resizeObserver?.disconnect()
    this.renderer?.domElement?.remove()
  },

  mountScene() {
    this.canvas = this.el.querySelector("[data-role='canvas']")
    this.label = this.el.querySelector("[data-role='label']")
    this.scene = new THREE.Scene()
    this.scene.fog = new THREE.FogExp2(palette.surface, 0.075)
    this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100)
    this.camera.position.set(0, -0.15, 9)
    this.renderer = new THREE.WebGLRenderer({antialias: true, alpha: true, powerPreference: "high-performance"})
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    this.renderer.setClearColor(0x000000, 0)
    this.renderer.outputColorSpace = THREE.SRGBColorSpace
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping
    this.renderer.toneMappingExposure = 1.14
    this.canvas.appendChild(this.renderer.domElement)

    this.controls = new OrbitControls(this.camera, this.renderer.domElement)
    this.controls.target.set(0, -0.35, 0)
    this.controls.enableDamping = true
    this.controls.dampingFactor = 0.075
    this.controls.minDistance = 4.8
    this.controls.maxDistance = 12
    this.controls.maxPolarAngle = Math.PI * 0.72
    this.cameraViews = {
      front: {position: [0, -0.15, 9], target: [0, -0.35, 0], label: "Vista frontal"},
      back: {position: [0, -0.15, -9], target: [0, -0.35, 0], label: "Vista trasera"},
      side: {position: [-9, -0.15, 0], target: [0, -0.35, 0], label: "Vista lateral"},
      left: {position: [-9, -0.15, 0], target: [0, -0.35, 0], label: "Vista izquierda"},
      right: {position: [9, -0.15, 0], target: [0, -0.35, 0], label: "Vista derecha"},
    }
    this.cameraViewPosition = this.camera.position.clone()
    this.cameraViewTarget = this.controls.target.clone()
    this.cameraViewAnimating = false
    this.el.querySelectorAll("[data-camera-view]").forEach((button) => {
      button.addEventListener("click", () => this.setCameraView(button.dataset.cameraView))
    })
    this.editorPanel = this.el.querySelector("[data-role='editor-panel']")
    this.editorStatus = this.el.querySelector("[data-role='editor-status']")
    this.editorInputs = this.el.querySelectorAll("[data-editor-transform]")
    this.editorAxis = "camera"
    this.el.querySelector("[data-role='edit-pose']")?.addEventListener("click", () => this.toggleEditor())
    this.el.querySelectorAll("[data-editor-action]").forEach((button) => {
      button.addEventListener("click", () => this.editorAction(button.dataset.editorAction))
    })
    this.el.querySelectorAll("[data-editor-axis]").forEach((button) => {
      button.addEventListener("click", () => this.setEditorAxis(button.dataset.editorAxis))
    })
    this.editorInputs.forEach((input) => input.addEventListener("input", () => this.updateTransform(input.dataset.editorTransform, input.value)))

    this.scene.add(new THREE.HemisphereLight(0xffe0b2, 0x142333, 2.4))
    const key = new THREE.DirectionalLight(0xffd8a7, 3.1)
    key.position.set(-3, 5, 5)
    this.scene.add(key)
    const rim = new THREE.DirectionalLight(0x71c7f5, 1.6)
    rim.position.set(4, 2, -4)
    this.scene.add(rim)

    this.groundY = -2.94
    const floor = new THREE.Mesh(
      new THREE.CircleGeometry(5.2, 64),
      new THREE.MeshBasicMaterial({color: 0x0b2331, transparent: true, opacity: 0.42, side: THREE.DoubleSide}),
    )
    floor.rotation.x = -Math.PI / 2
    floor.position.y = this.groundY
    this.scene.add(floor)
    const grid = new THREE.GridHelper(8, 16, 0x28526d, 0x163347)
    grid.position.y = this.groundY + 0.002
    ;(Array.isArray(grid.material) ? grid.material : [grid.material]).forEach((material) => {
      material.transparent = true
      material.opacity = 0.26
    })
    this.scene.add(grid)
    const axes = new THREE.AxesHelper(0.7)
    axes.position.set(-1.65, this.groundY + 0.01, 0)
    ;(Array.isArray(axes.material) ? axes.material : [axes.material]).forEach((material) => {
      material.transparent = true
      material.opacity = 0.55
    })
    this.scene.add(axes)

    this.buildBody()
    this.raycaster = new THREE.Raycaster()
    this.pointer = new THREE.Vector2()
    this.renderer.domElement.addEventListener("pointermove", (event) => this.hover(event))
    this.renderer.domElement.addEventListener("pointerdown", (event) => this.beginPointer(event))
    this.renderer.domElement.addEventListener("pointerup", (event) => this.tap(event))
    this.renderer.domElement.addEventListener("pointercancel", (event) => this.tap(event))
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.canvas)
    this.resize()
    this.animate()
  },

  buildBody() {
    const body = new THREE.Group()
    body.rotation.y = -0.16
    this.scene.add(body)
    this.body = body
    this.bodyBaseYaw = -0.16
    this.poseGroups = {}
    this.joints = new Map()
    this.muscles = new Map()
    this.interactive = []

    const wood = (color = 0xc69a5a) => new THREE.MeshStandardMaterial({
      color,
      roughness: 0.4,
      metalness: 0.035,
    })
    const mesh = (geometry, material, position, parent = body, scale = null) => {
      const part = new THREE.Mesh(geometry, material)
      part.position.set(...position)
      if (scale) part.scale.set(...scale)
      parent.add(part)
      return part
    }
    const sphere = (radius, position, parent = body, scale = null, color) =>
      mesh(new THREE.SphereGeometry(radius, 20, 16), wood(color), position, parent, scale)
    const segment = (top, bottom, length, position, parent = body, color) =>
      mesh(new THREE.CylinderGeometry(top, bottom, length, 14), wood(color), position, parent)
    const joint = (id, position, parent = body, editorGroup = null, distalGroup = null) => {
      const marker = new THREE.Mesh(
        new THREE.SphereGeometry(0.12, 16, 12),
        new THREE.MeshStandardMaterial({color: palette.line, roughness: 0.25, metalness: 0.45}),
      )
      marker.position.set(...position)
      marker.userData = {kind: "joint", id, editorGroup, distalGroup}
      marker.visible = false
      parent.add(marker)
      this.joints.set(`${id}-${this.joints.size}`, marker)
      this.interactive.push(marker)
    }
    const muscle = (id, geometry, position, parent = body) => {
      const isBack = position[2] < 0
      const plane = new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({
        color: palette.slate,
        transparent: true,
        opacity: 0.22,
        side: THREE.FrontSide,
        depthWrite: false,
      }))
      plane.position.set(...position)
      if (isBack) plane.rotation.y = Math.PI
      plane.userData = {kind: "muscle", id, side: isBack ? "back" : "front"}
      parent.add(plane)
      this.muscles.set(`${id}-${this.muscles.size}`, plane)
      this.interactive.push(plane)
    }

    const torso = new THREE.Group()
    torso.position.y = 0.22
    body.add(torso)
    this.poseGroups.torso = torso
    mesh(new THREE.CylinderGeometry(0.53, 0.38, 1.16, 14), wood(), [0, 0.3, 0], torso)
    sphere(0.42, [0, -0.62, 0], torso, [1.05, 0.78, 0.84])
    segment(0.17, 0.19, 0.22, [0, 1.0, 0], torso, 0x93643a)
    const head = mesh(
      new THREE.LatheGeometry([
        new THREE.Vector2(0.28, -0.57),
        new THREE.Vector2(0.45, -0.18),
        new THREE.Vector2(0.42, 0.44),
        new THREE.Vector2(0.25, 0.64),
      ], 20),
      wood(0xd6ad70),
      [0, 1.68, 0],
      torso,
    )
    head.scale.z = 0.86

    const limb = (side, kind) => {
      const isArm = kind === "arm"
      const editorGroup = `${side < 0 ? "left" : "right"}${isArm ? "Arm" : "Leg"}`
      const distalGroup = `${side < 0 ? "left" : "right"}${isArm ? "Elbow" : "Knee"}`
      const group = new THREE.Group()
      group.position.set(side * (isArm ? 0.69 : 0.36), isArm ? 1.0 : -0.65, 0)
      body.add(group)
      this.poseGroups[editorGroup] = group
      joint(isArm ? "shoulder" : "hip", [0, 0, 0], group, editorGroup)
      segment(isArm ? 0.16 : 0.22, isArm ? 0.2 : 0.27, isArm ? 0.78 : 1.02, [0, isArm ? -0.5 : -0.67, 0], group)
      const lower = new THREE.Group()
      lower.position.y = isArm ? -1.02 : -1.32
      group.add(lower)
      this.poseGroups[distalGroup] = lower
      joint(isArm ? "elbow" : "knee", [0, 0.02, 0], lower, editorGroup, distalGroup)
      sphere(isArm ? 0.17 : 0.22, [0, 0.02, 0], lower, [1, 0.86, 1], 0xa27342)
      segment(isArm ? 0.13 : 0.17, isArm ? 0.16 : 0.22, isArm ? 0.68 : 0.92, [0, isArm ? -0.42 : -0.58, 0], lower)
      if (isArm) {
        joint("wrist", [0, -0.82, 0], lower, distalGroup)
        sphere(0.16, [0, -0.95, 0.02], lower, [0.72, 1.45, 0.72])
      } else {
        joint("ankle", [0, -1.08, 0], lower, distalGroup)
        sphere(0.2, [0, -1.23, 0.13], lower, [0.78, 0.55, 1.4])
      }
      return {group, lower}
    }

    const leftArm = limb(-1, "arm")
    const rightArm = limb(1, "arm")
    const leftLeg = limb(-1, "leg")
    const rightLeg = limb(1, "leg")
    joint("tspine", [0, 0.48, -0.45], torso, "torso")

    this.propObjects = {dumbbells: {}, blocks: {}}
    const dumbbell = (parent, position) => {
      const group = new THREE.Group()
      const handleMaterial = new THREE.MeshStandardMaterial({color: 0x1b2637, roughness: 0.24, metalness: 0.78})
      const plateMaterial = new THREE.MeshStandardMaterial({color: 0x2563eb, roughness: 0.24, metalness: 0.46, emissive: 0x071226, emissiveIntensity: 0.38})
      const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.052, 0.052, 0.62, 12), handleMaterial)
      handle.rotation.z = Math.PI / 2
      group.add(handle)
      ;[-0.39, 0.39].forEach((x) => {
        const plate = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 0.12, 16), plateMaterial)
        plate.rotation.z = Math.PI / 2
        plate.position.x = x
        group.add(plate)
      })
      group.position.set(...position)
      group.visible = false
      group.userData = {plateMaterial}
      parent.add(group)
      return group
    }
    this.propObjects.dumbbells.left = dumbbell(leftArm.lower, [0, -0.92, 0.12])
    this.propObjects.dumbbells.right = dumbbell(rightArm.lower, [0, -0.92, 0.12])
    this.propObjects.dumbbells.front = dumbbell(torso, [0, 0.28, 0.66])

    const block = (position) => {
      const group = new THREE.Group()
      const material = new THREE.MeshStandardMaterial({color: 0x1e4c66, roughness: 0.52, metalness: 0.18, emissive: 0x061827, emissiveIntensity: 0.3})
      const topMaterial = new THREE.MeshStandardMaterial({color: 0x4f9bc0, roughness: 0.42, metalness: 0.1})
      const base = new THREE.Mesh(new THREE.BoxGeometry(0.92, 0.46, 0.68), material)
      const top = new THREE.Mesh(new THREE.BoxGeometry(0.98, 0.055, 0.74), topMaterial)
      top.position.y = 0.255
      group.add(base, top)
      group.position.set(...position)
      group.visible = false
      this.scene.add(group)
      return group
    }
    this.propObjects.blocks.rear = block([0.62, this.groundY + 0.25, -0.36])
    this.propObjects.blocks.front = block([0, this.groundY + 0.25, 0.7])
    this.propObjects.blocks.side = block([-0.95, this.groundY + 0.25, 0.08])

    // Flat translucent planes follow the mannequin's real groups. Front planes
    // become visible from the front; posterior planes reveal themselves on rotation.
    muscle("chest", trapezoid(0.35, 0.3, 0.42), [-0.21, 0.45, 0.43], torso)
    muscle("chest", trapezoid(0.35, 0.3, 0.42), [0.21, 0.45, 0.43], torso)
    muscle("core", trapezoid(0.28, 0.34, 0.52), [0, -0.1, 0.4], torso)
    muscle("obliques", polygon([[-0.16, 0.26], [0.16, 0.2], [0.12, -0.25], [-0.2, -0.18]]), [-0.39, -0.08, 0.36], torso)
    muscle("obliques", polygon([[-0.16, 0.2], [0.16, 0.26], [0.2, -0.18], [-0.12, -0.25]]), [0.39, -0.08, 0.36], torso)
    muscle("shoulders", new THREE.CircleGeometry(0.2, 14), [-0.69, 1.08, 0.18])
    muscle("shoulders", new THREE.CircleGeometry(0.2, 14), [0.69, 1.08, 0.18])
    muscle("arms", trapezoid(0.25, 0.21, 0.68), [0, -0.5, 0.205], leftArm.group)
    muscle("arms", trapezoid(0.25, 0.21, 0.68), [0, -0.5, 0.205], rightArm.group)
    muscle("grip", trapezoid(0.18, 0.13, 0.48), [0, -0.42, 0.17], leftArm.lower)
    muscle("grip", trapezoid(0.18, 0.13, 0.48), [0, -0.42, 0.17], rightArm.lower)
    muscle("quads", trapezoid(0.34, 0.28, 0.86), [0, -0.65, 0.275], leftLeg.group)
    muscle("quads", trapezoid(0.34, 0.28, 0.86), [0, -0.65, 0.275], rightLeg.group)

    muscle("traps", trapezoid(0.98, 0.42, 0.24), [0, 0.84, -0.4], torso)
    muscle("upperback", trapezoid(0.43, 0.34, 0.52), [-0.22, 0.37, -0.44], torso)
    muscle("upperback", trapezoid(0.43, 0.34, 0.52), [0.22, 0.37, -0.44], torso)
    muscle("erectors", trapezoid(0.1, 0.12, 0.72), [-0.13, -0.12, -0.43], torso)
    muscle("erectors", trapezoid(0.1, 0.12, 0.72), [0.13, -0.12, -0.43], torso)
    muscle("glutes", trapezoid(0.32, 0.35, 0.3), [-0.22, -0.66, -0.35], torso)
    muscle("glutes", trapezoid(0.32, 0.35, 0.3), [0.22, -0.66, -0.35], torso)
    muscle("shoulders", new THREE.CircleGeometry(0.2, 14), [-0.69, 1.08, -0.18])
    muscle("shoulders", new THREE.CircleGeometry(0.2, 14), [0.69, 1.08, -0.18])
    muscle("arms", trapezoid(0.25, 0.21, 0.68), [0, -0.5, -0.205], leftArm.group)
    muscle("arms", trapezoid(0.25, 0.21, 0.68), [0, -0.5, -0.205], rightArm.group)
    muscle("grip", trapezoid(0.18, 0.13, 0.48), [0, -0.42, -0.17], leftArm.lower)
    muscle("grip", trapezoid(0.18, 0.13, 0.48), [0, -0.42, -0.17], rightArm.lower)
    muscle("hams", trapezoid(0.34, 0.28, 0.86), [0, -0.65, -0.275], leftLeg.group)
    muscle("hams", trapezoid(0.34, 0.28, 0.86), [0, -0.65, -0.275], rightLeg.group)
  },

  sync() {
    this.state = {
      mode: this.el.dataset.mode || "binary",
      active: parse(this.el.dataset.active, []),
      levels: parse(this.el.dataset.levels, {}),
      colors: parse(this.el.dataset.colors, {}),
      joints: parse(this.el.dataset.joints, []),
      pose: this.el.dataset.pose || "neutral",
      poseKey: this.el.dataset.poseKey || this.el.dataset.pose || "neutral",
      poseSettings: parse(this.el.dataset.poseSettings, {}),
      props: parse(this.el.dataset.props, []),
      event: this.el.dataset.bodyEvent || "",
    }
    if (!this.editMode) this.applyPoseSettings(this.state.poseSettings)
    this.syncProps()
    this.muscles.forEach((plane) => {
      const {id} = plane.userData
      let color = "#506579"
      if (this.state.mode === "binary") color = this.state.active.includes(id) ? "#38bdf8" : "#506579"
      if (this.state.mode === "heat") color = heat(this.state.levels[id])
      if (this.state.mode === "direct") color = this.state.colors[id] || "#9ec6e0"
      plane.material.color.set(color)
      const isColored =
        (this.state.mode === "binary" && this.state.active.includes(id)) ||
        (this.state.mode === "direct" && this.state.active.includes(id)) ||
        (this.state.mode === "heat" && Boolean(this.state.levels[id]))
      plane.material.opacity = this.state.mode === "joints" ? 0 : (isColored ? 0.92 : 0.58)
      plane.visible = this.state.mode !== "joints"
    })
    this.joints.forEach((marker) => {
      const selected = this.state.joints.length === 0 || this.state.joints.includes(marker.userData.id)
      marker.visible = this.state.mode === "joints" || this.editMode
      marker.material.color.set(this.editMode ? 0xfbbf24 : (selected ? palette.cyan : palette.line))
      marker.material.emissive.set(this.editMode ? 0x5b3a00 : (selected ? palette.cyan : 0x000000))
      marker.scale.setScalar(this.editMode ? 1.65 : (selected ? 1.18 : 0.78))
    })
  },

  syncProps() {
    if (!this.propObjects) return
    Object.values(this.propObjects.dumbbells).forEach((prop) => { prop.visible = false })
    Object.values(this.propObjects.blocks).forEach((prop) => { prop.visible = false })
    const weights = {
      light: {color: 0x7dd3fc, scale: 0.76},
      medium: {color: 0x2563eb, scale: 1},
      heavy: {color: 0x7c3aed, scale: 1.28},
    }
    this.state.props.forEach((prop) => {
      if (prop.kind === "dumbbell") {
        const hands = prop.hand === "both" ? ["left", "right"] : [prop.hand]
        const weight = weights[prop.weight] || weights.medium
        hands.forEach((hand) => {
          const dumbbell = this.propObjects.dumbbells[hand]
          if (!dumbbell) return
          dumbbell.visible = true
          dumbbell.scale.setScalar(weight.scale)
          dumbbell.userData.plateMaterial.color.setHex(weight.color)
          dumbbell.userData.plateMaterial.emissive.setHex(weight.color)
        })
      }
      if (prop.kind === "block") {
        const block = this.propObjects.blocks[prop.position]
        if (block) block.visible = true
      }
    })
  },

  resize() {
    const {width, height} = this.canvas.getBoundingClientRect()
    if (!width || !height) return
    this.camera.aspect = width / height
    this.camera.updateProjectionMatrix()
    this.renderer.setSize(width, height)
  },

  pick(event) {
    const candidates = (this.state.mode === "joints" || this.editMode) ? [...this.joints.values()] : [...this.muscles.values()]
    const rect = this.renderer.domElement.getBoundingClientRect()
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1
    this.raycaster.setFromCamera(this.pointer, this.camera)
    return this.raycaster.intersectObjects(candidates, false)[0]?.object
  },

  hover(event) {
    if (this.editorDrag) return this.dragJoint(event)
    const object = this.pick(event)
    this.renderer.domElement.style.cursor = object ? "pointer" : "grab"
    if (object) {
      const kind = object.userData.kind === "joint" ? "Articulación" : "Músculo"
      this.label.textContent = `${kind}: ${object.userData.id}`
    }
  },

  tap(event) {
    if (this.editorDrag) {
      this.settleDistal(this.editorDrag)
      this.editorDrag = null
      this.controls.enabled = true
      this.groundToPlane()
      return
    }
    if (!this.down || Math.hypot(event.clientX - this.down[0], event.clientY - this.down[1]) > 5) return
    const object = this.pick(event)
    if (!object || !this.state.event) return
    const key = object.userData.kind === "joint" ? "joint" : "muscle"
    this.pushEvent(this.state.event, {[key]: object.userData.id})
  },

  setCameraView(name) {
    const view = this.cameraViews[name]
    if (!view) return
    this.cameraViewPosition.set(...view.position)
    this.cameraViewTarget.set(...view.target)
    this.cameraViewAnimating = true
    this.el.querySelectorAll("[data-camera-view]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.cameraView === name))
    })
    this.label.textContent = `${view.label} · toca una capa para filtrar`
  },

  applyPoseSettings(settings = {}) {
    const defaults = {
      joints: {},
      transform: {x: 0, y: 0, z: 0, rotationX: 0, rotationY: 0, rotationZ: 0},
      camera: null,
    }
    this.editorSettings = {
      ...defaults,
      ...settings,
      joints: Object.fromEntries(Object.entries(settings.joints || {}).map(([key, value]) => [key, rotation(value)])),
      transform: {...defaults.transform, ...(settings.transform || {})},
    }
    this.targetPose = targetsFor(this.state.pose, this.editorSettings.joints)
    const transform = this.editorSettings.transform
    this.body.position.set(Number(transform.x) || 0, Number(transform.y) || 0, Number(transform.z) || 0)
    this.body.rotation.set(
      Number(transform.rotationX) || 0,
      this.bodyBaseYaw + (Number(transform.rotationY) || Number(transform.yaw) || 0),
      Number(transform.rotationZ) || 0,
    )
    if (this.editorSettings.camera?.position?.length === 3 && this.editorSettings.camera?.target?.length === 3) {
      this.camera.position.set(...this.editorSettings.camera.position)
      this.controls.target.set(...this.editorSettings.camera.target)
      this.cameraViewAnimating = false
    }
    this.syncEditorInputs()
  },

  toggleEditor() {
    this.editMode = !this.editMode
    this.editorPanel.hidden = !this.editMode
    this.editorStatus.textContent = this.editMode
      ? "Arrastra hombros, codos, muñecas, caderas, rodillas o tobillos. Auto plano usa el eje que más se aprecia desde la cámara."
      : "Editor cerrado."
    this.label.textContent = this.editMode ? "Editor activo · arrastra un punto articular" : "Arrastra para rotar · gira para ver frente y espalda"
    this.sync()
  },

  editorAction(action) {
    if (action === "close") return this.toggleEditor()
    if (action === "ground") return this.groundToPlane()
    if (action === "reset") {
      this.applyPoseSettings({})
      this.editorStatus.textContent = "Postura restablecida localmente. Guarda para conservar el cambio."
      return
    }
    if (action === "save") {
      const settings = {
        joints: this.editorSettings.joints,
        transform: this.editorSettings.transform,
        camera: {position: this.camera.position.toArray(), target: this.controls.target.toArray()},
      }
      this.pushEvent("strength:save_pose", {pose: this.state.poseKey, settings})
      this.editorStatus.textContent = "Guardando postura en tu vault personal…"
    }
  },

  setEditorAxis(axis) {
    this.editorAxis = axis
    this.el.querySelectorAll("[data-editor-axis]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.editorAxis === axis))
    })
    this.editorStatus.textContent = axis === "camera"
      ? "Auto plano: el gesto elige el eje más prominente para la cámara actual."
      : `Eje ${axis.toUpperCase()} activo para el siguiente ajuste articular.`
  },

  updateTransform(key, value) {
    const names = {"rotation-x": "rotationX", "rotation-y": "rotationY", "rotation-z": "rotationZ"}
    this.editorSettings.transform[names[key] || key] = Number(value)
    this.applyPoseSettings({...this.editorSettings, camera: null})
  },

  syncEditorInputs() {
    const names = {"rotation-x": "rotationX", "rotation-y": "rotationY", "rotation-z": "rotationZ"}
    this.editorInputs?.forEach((input) => { input.value = this.editorSettings.transform[names[input.dataset.editorTransform] || input.dataset.editorTransform] || 0 })
  },

  beginPointer(event) {
    this.down = [event.clientX, event.clientY]
    if (!this.editMode) return
    const object = this.pick(event)
    if (!object?.userData.editorGroup) return
    this.editorDrag = {
      group: object.userData.editorGroup,
      distalGroup: object.userData.distalGroup,
      joint: object.userData.id,
      x: event.clientX,
      y: event.clientY,
    }
    this.controls.enabled = false
    this.label.textContent = `Editando: ${object.userData.id}`
  },

  dragJoint(event) {
    const drag = this.editorDrag
    const axis = this.resolveDragAxis()
    const distance = axis === "x" ? event.clientY - drag.y : event.clientX - drag.x
    drag.x = event.clientX
    drag.y = event.clientY
    const offset = rotation(this.editorSettings.joints[drag.group])
    offset[axis] = THREE.MathUtils.clamp(offset[axis] + distance * 0.012, -3.14, 3.14)
    this.editorSettings.joints[drag.group] = offset
    this.targetPose = targetsFor(this.state.pose, this.editorSettings.joints)
    this.label.textContent = `Editando ${drag.joint} en eje ${axis.toUpperCase()} · suelta para asentar`
  },

  resolveDragAxis() {
    if (this.editorAxis && this.editorAxis !== "camera") return this.editorAxis
    const direction = this.camera.getWorldDirection(new THREE.Vector3())
    return Math.abs(direction.z) > Math.abs(direction.x) ? "z" : "x"
  },

  settleDistal(drag) {
    if (drag.joint !== "elbow" && drag.joint !== "knee") return
    const parent = rotation(this.editorSettings.joints[drag.group])
    const distal = rotation(this.editorSettings.joints[drag.distalGroup])
    distal.x = -parent.x * 0.72
    distal.z = -parent.z * 0.72
    this.editorSettings.joints[drag.distalGroup] = distal
    this.targetPose = targetsFor(this.state.pose, this.editorSettings.joints)
  },

  groundToPlane() {
    this.body.updateMatrixWorld(true)
    const supports = [...this.joints.values()].filter((marker) => ["wrist", "ankle", "elbow", "knee"].includes(marker.userData.id))
    const lowest = supports.reduce((minimum, marker) => Math.min(minimum, marker.getWorldPosition(new THREE.Vector3()).y), Infinity)
    if (!Number.isFinite(lowest)) return
    const delta = this.groundY - lowest
    this.body.position.y += delta
    this.editorSettings.transform.y = (Number(this.editorSettings.transform.y) || 0) + delta
    this.syncEditorInputs()
    this.editorStatus.textContent = "Gravedad aplicada: el joint de soporte inferior toca el plano."
  },

  animate() {
    this.animationFrame = requestAnimationFrame(() => this.animate())
    if (this.targetPose) Object.entries(this.targetPose).forEach(([name, target]) => {
      const group = this.poseGroups[name]
      if (!group) return
      group.rotation.x = THREE.MathUtils.lerp(group.rotation.x, target.x, 0.085)
      group.rotation.y = THREE.MathUtils.lerp(group.rotation.y, target.y, 0.085)
      group.rotation.z = THREE.MathUtils.lerp(group.rotation.z, target.z, 0.085)
    })
    if (this.cameraViewAnimating) {
      this.camera.position.lerp(this.cameraViewPosition, 0.14)
      this.controls.target.lerp(this.cameraViewTarget, 0.14)
      if (this.camera.position.distanceTo(this.cameraViewPosition) < 0.02 && this.controls.target.distanceTo(this.cameraViewTarget) < 0.02) {
        this.cameraViewAnimating = false
      }
    }
    this.controls.update()
    this.renderer.render(this.scene, this.camera)
  },
}
