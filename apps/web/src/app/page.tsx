import { Nav } from "@/components/landing/nav";
import { Hero } from "@/components/landing/hero";
import { Mosaic } from "@/components/landing/mosaic";
import { Story } from "@/components/landing/story";
import { Amenities } from "@/components/landing/amenities";
import { Rooms } from "@/components/landing/rooms";
import { Food } from "@/components/landing/food";
import { DepositPromise } from "@/components/landing/promise";
import { Join } from "@/components/landing/join";
import { Faq } from "@/components/landing/faq";
import { Footer, Visit } from "@/components/landing/footer";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Mosaic />
        <Story />
        <Amenities />
        <Rooms />
        <Food />
        <DepositPromise />
        <Join />
        <Faq />
        <Visit />
      </main>
      <Footer />
    </>
  );
}
