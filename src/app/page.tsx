'use client';

import HeroSection from '@/components/HeroSection';
import FeaturesSection from '@/components/FeaturesSection';
import ArchitectureSection from '@/components/ArchitectureSection';
import QuickStartSection from '@/components/QuickStartSection';
import FileExplorerSection from '@/components/FileExplorerSection';
import ComparisonSection from '@/components/ComparisonSection';
import DownloadSection from '@/components/DownloadSection';
import Footer from '@/components/Footer';

export default function Home() {
  return (
    <div className="min-h-screen flex flex-col bg-gray-950">
      <main className="flex-1">
        <HeroSection />
        <FeaturesSection />
        <ArchitectureSection />
        <QuickStartSection />
        <FileExplorerSection />
        <ComparisonSection />
        <DownloadSection />
      </main>
      <Footer />
    </div>
  );
}
