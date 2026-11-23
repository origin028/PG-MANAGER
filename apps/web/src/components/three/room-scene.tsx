"use client";
import { Canvas, useFrame } from "@react-three/fiber";
import { ContactShadows, PresentationControls, RoundedBox } from "@react-three/drei";
import { useRef, type RefObject } from "react";
import { Vector3, type Group } from "three";
import type { MotionValue } from "motion/react";

/** Palette: cream + black, matching the site. */
const C = {
  floor: "#eadfcb", wall: "#fffdf8", wallSide: "#f8f3ea", white: "#fbfaf7", black: "#111111",
  wood: "#c9a97f", rug: "#e2d8c6", leaf: "#4f6b4a", glass: "#dbe8ef",
};

function Box({ args, position, color, rotation }: { args: [number, number, number]; position: [number, number, number]; color: string; rotation?: [number, number, number] }) {
  return (
    <mesh position={position} rotation={rotation} castShadow receiveShadow>
      <boxGeometry args={args} />
      <meshStandardMaterial color={color} roughness={0.85} />
    </mesh>
  );
}

/** Labels live in normal DOM (outside the canvas); each frame we project their 3D anchor to screen space. */
const TAGS: { label: string; at: [number, number, number] }[] = [
  { label: "Fully furnished bed", at: [1.5, 1.45, -1.2] },
  { label: "Personal wardrobe", at: [-1.9, 2.75, -2.6] },
  { label: "Study desk", at: [-2.4, 1.6, 0.75] },
];

function TagTracker({ group, els }: { group: RefObject<Group | null>; els: RefObject<(HTMLSpanElement | null)[]> }) {
  const v = new Vector3();
  useFrame(({ camera, size }) => {
    if (!group.current) return;
    TAGS.forEach((t, i) => {
      const el = els.current?.[i];
      if (!el) return;
      v.set(...t.at).applyMatrix4(group.current!.matrixWorld).project(camera);
      el.style.transform = `translate(-50%, -50%) translate(${((v.x + 1) / 2) * size.width}px, ${((1 - v.y) / 2) * size.height}px)`;
      el.style.opacity = v.z < 1 ? "1" : "0";
    });
  });
  return null;
}

function Room({ scroll, reduce, els }: { scroll?: MotionValue<number>; reduce: boolean; els: RefObject<(HTMLSpanElement | null)[]> }) {
  const g = useRef<Group>(null);
  useFrame((state) => {
    if (!g.current) return;
    const s = scroll?.get() ?? 0;
    const idle = reduce ? 0 : Math.sin(state.clock.elapsedTime * 0.35) * 0.06;
    g.current.rotation.y = -0.15 + s * 0.9 + idle;
  });

  return (
    <group ref={g} position={[0, -0.9, 0]}>
      {/* Shell */}
      <Box args={[6, 0.12, 6]} position={[0, -0.06, 0]} color={C.floor} />
      <Box args={[6, 3.2, 0.12]} position={[0, 1.6, -3]} color={C.wall} />
      <Box args={[0.12, 3.2, 6]} position={[-3, 1.6, 0]} color={C.wallSide} />
      <mesh position={[0.6, 0.005, 0.9]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <circleGeometry args={[1.35, 48]} />
        <meshStandardMaterial color={C.rug} roughness={1} />
      </mesh>

      {/* Window on the side wall, glowing daylight */}
      <Box args={[0.06, 1.5, 1.9]} position={[-2.93, 1.95, 0.7]} color={C.white} />
      <mesh position={[-2.89, 1.95, 0.7]} rotation={[0, Math.PI / 2, 0]}>
        <planeGeometry args={[1.7, 1.3]} />
        <meshStandardMaterial color={C.glass} emissive="#ffffff" emissiveIntensity={0.9} />
      </mesh>

      {/* Bed */}
      <Box args={[2.3, 0.4, 3]} position={[1.5, 0.2, -1.45]} color={C.wood} />
      <RoundedBox args={[2.15, 0.32, 2.85]} radius={0.08} position={[1.5, 0.56, -1.45]} castShadow>
        <meshStandardMaterial color={C.white} roughness={0.9} />
      </RoundedBox>
      <RoundedBox args={[2.2, 0.1, 1.7]} radius={0.04} position={[1.5, 0.76, -0.75]} castShadow>
        <meshStandardMaterial color={C.black} roughness={0.9} />
      </RoundedBox>
      <RoundedBox args={[0.8, 0.18, 0.45]} radius={0.08} position={[1.05, 0.82, -2.55]} castShadow><meshStandardMaterial color={C.white} /></RoundedBox>
      <RoundedBox args={[0.8, 0.18, 0.45]} radius={0.08} position={[1.95, 0.82, -2.55]} castShadow><meshStandardMaterial color={C.white} /></RoundedBox>
      <Box args={[2.4, 1.1, 0.12]} position={[1.5, 0.95, -2.92]} color={C.wood} />

      {/* Bedside table + lamp */}
      <Box args={[0.55, 0.55, 0.55]} position={[-0.05, 0.28, -2.55]} color={C.white} />
      <mesh position={[-0.05, 0.75, -2.55]} castShadow>
        <cylinderGeometry args={[0.03, 0.03, 0.4]} />
        <meshStandardMaterial color={C.black} />
      </mesh>
      <mesh position={[-0.05, 1.0, -2.55]}>
        <sphereGeometry args={[0.16, 24, 24]} />
        <meshStandardMaterial color="#fff3d6" emissive="#ffd99a" emissiveIntensity={1.4} />
      </mesh>
      <pointLight position={[-0.05, 1.05, -2.4]} intensity={2.2} distance={3.5} color="#ffd9a0" />

      {/* Wardrobe */}
      <Box args={[1.5, 2.5, 0.7]} position={[-1.9, 1.25, -2.6]} color={C.white} />
      <Box args={[0.02, 2.4, 0.02]} position={[-1.9, 1.25, -2.24]} color="#d9d2c3" />
      <Box args={[0.04, 0.4, 0.04]} position={[-2.0, 1.3, -2.22]} color={C.black} />
      <Box args={[0.04, 0.4, 0.04]} position={[-1.8, 1.3, -2.22]} color={C.black} />

      {/* Study desk, chair, laptop */}
      <Box args={[0.75, 0.07, 1.7]} position={[-2.55, 0.95, 0.75]} color={C.wood} />
      {[[-2.85, 0.1], [-2.85, 1.45], [-2.25, 0.1], [-2.25, 1.45]].map(([x, z]) => (
        <Box key={`${x}${z}`} args={[0.05, 0.92, 0.05]} position={[x, 0.46, z]} color={C.black} />
      ))}
      <Box args={[0.45, 0.02, 0.6]} position={[-2.55, 1.0, 0.75]} color="#2a2a2a" />
      <Box args={[0.02, 0.35, 0.6]} position={[-2.78, 1.17, 0.75]} color="#2a2a2a" rotation={[0, 0, 0.2]} />
      <Box args={[0.6, 0.07, 0.6]} position={[-1.75, 0.55, 0.75]} color={C.black} />
      <Box args={[0.07, 0.65, 0.6]} position={[-1.45, 0.85, 0.75]} color={C.black} />
      {[[-2.0, 0.5], [-2.0, 1.0], [-1.5, 0.5], [-1.5, 1.0]].map(([x, z]) => (
        <Box key={`c${x}${z}`} args={[0.04, 0.52, 0.04]} position={[x, 0.26, z]} color={C.black} />
      ))}

      {/* Plant */}
      <mesh position={[2.45, 0.25, 1.9]} castShadow>
        <cylinderGeometry args={[0.22, 0.17, 0.5, 24]} />
        <meshStandardMaterial color={C.white} />
      </mesh>
      <mesh position={[2.45, 0.85, 1.9]} castShadow>
        <sphereGeometry args={[0.42, 20, 20]} />
        <meshStandardMaterial color={C.leaf} roughness={1} />
      </mesh>

      <TagTracker group={g} els={els} />
    </group>
  );
}

export default function RoomScene({ scroll, reduce = false }: { scroll?: MotionValue<number>; reduce?: boolean }) {
  const els = useRef<(HTMLSpanElement | null)[]>([]);
  return (
    <div className="relative h-full w-full">
      <Canvas shadows dpr={[1, 2]} camera={{ position: [7.5, 5.2, 7.5], fov: 32 }} gl={{ antialias: true }}>
        <ambientLight intensity={1.15} />
        <directionalLight position={[-4, 9, 6]} intensity={1.9} castShadow shadow-mapSize={[2048, 2048]} />
        <hemisphereLight args={["#ffffff", "#eadfcb", 0.8]} />
        <PresentationControls global={false} cursor snap rotation={[0, 0, 0]} polar={[-0.1, 0.2]} azimuth={[-0.6, 0.6]}>
          <Room scroll={scroll} reduce={reduce} els={els} />
        </PresentationControls>
        <ContactShadows position={[0, -0.97, 0]} opacity={0.35} scale={14} blur={2.5} far={4} />
      </Canvas>
      {TAGS.map((t, i) => (
        <span
          key={t.label}
          ref={(el) => { els.current[i] = el; }}
          className="glass pointer-events-none absolute top-0 left-0 whitespace-nowrap rounded-full px-3 py-1.5 text-[13px] font-medium opacity-0 will-change-transform"
        >
          {t.label}
        </span>
      ))}
    </div>
  );
}
