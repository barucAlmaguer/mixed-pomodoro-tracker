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
}[name] || poseFor("neutral"))

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

    this.scene.add(new THREE.HemisphereLight(0xffe0b2, 0x142333, 2.4))
    const key = new THREE.DirectionalLight(0xffd8a7, 3.1)
    key.position.set(-3, 5, 5)
    this.scene.add(key)
    const rim = new THREE.DirectionalLight(0x71c7f5, 1.6)
    rim.position.set(4, 2, -4)
    this.scene.add(rim)

    const floor = new THREE.Mesh(
      new THREE.CircleGeometry(2.4, 48),
      new THREE.MeshBasicMaterial({color: 0x14283a, transparent: true, opacity: 0.66}),
    )
    floor.rotation.x = -Math.PI / 2
    floor.position.y = -3.02
    this.scene.add(floor)

    this.buildBody()
    this.raycaster = new THREE.Raycaster()
    this.pointer = new THREE.Vector2()
    this.renderer.domElement.addEventListener("pointermove", (event) => this.hover(event))
    this.renderer.domElement.addEventListener("pointerdown", (event) => { this.down = [event.clientX, event.clientY] })
    this.renderer.domElement.addEventListener("pointerup", (event) => this.tap(event))
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.canvas)
    this.resize()
    this.animate()
  },

  buildBody() {
    const body = new THREE.Group()
    body.rotation.y = -0.16
    this.scene.add(body)
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
    const joint = (id, position, parent = body) => {
      const marker = new THREE.Mesh(
        new THREE.SphereGeometry(0.12, 16, 12),
        new THREE.MeshStandardMaterial({color: palette.line, roughness: 0.25, metalness: 0.45}),
      )
      marker.position.set(...position)
      marker.userData = {kind: "joint", id}
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

    mesh(new THREE.CylinderGeometry(1.2, 1.28, 0.18, 48), wood(0x704a29), [0, -2.94, 0])
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
      const group = new THREE.Group()
      group.position.set(side * (isArm ? 0.69 : 0.36), isArm ? 1.0 : -0.65, 0)
      body.add(group)
      this.poseGroups[`${side < 0 ? "left" : "right"}${isArm ? "Arm" : "Leg"}`] = group
      joint(isArm ? "shoulder" : "hip", [0, 0, 0], group)
      segment(isArm ? 0.16 : 0.22, isArm ? 0.2 : 0.27, isArm ? 0.78 : 1.02, [0, isArm ? -0.5 : -0.67, 0], group)
      const lower = new THREE.Group()
      lower.position.y = isArm ? -1.02 : -1.32
      group.add(lower)
      sphere(isArm ? 0.17 : 0.22, [0, 0.02, 0], lower, [1, 0.86, 1], 0xa27342)
      segment(isArm ? 0.13 : 0.17, isArm ? 0.16 : 0.22, isArm ? 0.68 : 0.92, [0, isArm ? -0.42 : -0.58, 0], lower)
      if (isArm) {
        joint("wrist", [0, -0.82, 0], lower)
        sphere(0.16, [0, -0.95, 0.02], lower, [0.72, 1.45, 0.72])
      } else {
        joint("ankle", [0, -1.08, 0], lower)
        sphere(0.2, [0, -1.23, 0.13], lower, [0.78, 0.55, 1.4])
      }
      return {group, lower}
    }

    const leftArm = limb(-1, "arm")
    const rightArm = limb(1, "arm")
    const leftLeg = limb(-1, "leg")
    const rightLeg = limb(1, "leg")
    joint("tspine", [0, 0.48, -0.45], torso)

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
      event: this.el.dataset.bodyEvent || "",
    }
    this.targetPose = poseFor(this.state.pose)
    this.muscles.forEach((plane) => {
      const {id} = plane.userData
      let color = "#506579"
      if (this.state.mode === "binary") color = this.state.active.includes(id) ? "#38bdf8" : "#506579"
      if (this.state.mode === "heat") color = heat(this.state.levels[id])
      if (this.state.mode === "direct") color = this.state.colors[id] || "#9ec6e0"
      plane.material.color.set(color)
      plane.material.opacity = this.state.mode === "joints" ? 0 : (this.state.active.includes(id) ? 0.74 : 0.42)
      plane.visible = this.state.mode !== "joints"
    })
    this.joints.forEach((marker) => {
      const selected = this.state.joints.length === 0 || this.state.joints.includes(marker.userData.id)
      marker.visible = this.state.mode === "joints"
      marker.material.color.set(selected ? palette.cyan : palette.line)
      marker.material.emissive.set(selected ? palette.cyan : 0x000000)
      marker.scale.setScalar(selected ? 1.18 : 0.78)
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
    const candidates = this.state.mode === "joints" ? [...this.joints.values()] : [...this.muscles.values()]
    const rect = this.renderer.domElement.getBoundingClientRect()
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1
    this.raycaster.setFromCamera(this.pointer, this.camera)
    return this.raycaster.intersectObjects(candidates, false)[0]?.object
  },

  hover(event) {
    const object = this.pick(event)
    this.renderer.domElement.style.cursor = object ? "pointer" : "grab"
    if (object) {
      const kind = object.userData.kind === "joint" ? "Articulación" : "Músculo"
      this.label.textContent = `${kind}: ${object.userData.id}`
    }
  },

  tap(event) {
    if (!this.down || Math.hypot(event.clientX - this.down[0], event.clientY - this.down[1]) > 5) return
    const object = this.pick(event)
    if (!object || !this.state.event) return
    const key = object.userData.kind === "joint" ? "joint" : "muscle"
    this.pushEvent(this.state.event, {[key]: object.userData.id})
  },

  animate() {
    this.animationFrame = requestAnimationFrame(() => this.animate())
    if (this.targetPose) Object.entries(this.targetPose).forEach(([name, target]) => {
      const group = this.poseGroups[name]
      if (group) group.rotation.x = THREE.MathUtils.lerp(group.rotation.x, target, 0.085)
    })
    this.controls.update()
    this.renderer.render(this.scene, this.camera)
  },
}
