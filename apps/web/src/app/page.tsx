import { Nav } from "@/components/landing/nav";
import { DepositPromise, Hero, Homes, Included, Join } from "@/components/landing/sections";
import { Footer, Visit } from "@/components/landing/footer";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Homes />
        <Included />
        <Join />
        <DepositPromise />
        <Visit />
      </main>
      <Footer />
    </>
  );
}
