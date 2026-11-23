import { Nav } from "@/components/landing/nav";
import { Hero } from "@/components/landing/hero";
import { Story } from "@/components/landing/story";
import { Rooms } from "@/components/landing/rooms";
import { Highlights } from "@/components/landing/highlights";
import { DepositPromise } from "@/components/landing/promise";
import { Join } from "@/components/landing/join";
import { Footer, Visit } from "@/components/landing/footer";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Story />
        <Rooms />
        <Highlights />
        <DepositPromise />
        <Join />
        <Visit />
      </main>
      <Footer />
    </>
  );
}
