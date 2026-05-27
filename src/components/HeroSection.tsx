'use client';

import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Monitor, Github, Terminal, ChevronRight } from 'lucide-react';

const terminalLines = [
  '$ git clone https://github.com/ilysenko/codex-desktop-linux.git',
  '$ cd codex-desktop-linux',
  '$ .\\install.ps1',
  '⠋ Downloading Codex Desktop DMG...',
  '⠙ Extracting application bundle...',
  '⠹ Patching ASAR for Windows...',
  '⠸ Downloading Electron runtime...',
  '⠼ Rebuilding native modules...',
  '⠦ Installing plugins...',
  '✅ Installation complete!',
  '$ .\\start.ps1',
  '🚀 Codex Desktop launched successfully!',
];

export default function HeroSection() {
  const scrollToSetup = () => {
    document.getElementById('quick-start')?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <section className="relative min-h-[90vh] flex items-center justify-center overflow-hidden">
      {/* Gradient background */}
      <div className="absolute inset-0 bg-gradient-to-br from-gray-950 via-gray-900 to-emerald-950" />

      {/* Animated gradient orbs */}
      <motion.div
        className="absolute top-1/4 -left-32 w-96 h-96 rounded-full bg-emerald-500/10 blur-3xl"
        animate={{
          scale: [1, 1.2, 1],
          opacity: [0.3, 0.5, 0.3],
        }}
        transition={{ duration: 8, repeat: Infinity, ease: 'easeInOut' }}
      />
      <motion.div
        className="absolute bottom-1/4 -right-32 w-96 h-96 rounded-full bg-teal-500/10 blur-3xl"
        animate={{
          scale: [1.2, 1, 1.2],
          opacity: [0.5, 0.3, 0.5],
        }}
        transition={{ duration: 8, repeat: Infinity, ease: 'easeInOut' }}
      />
      <motion.div
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] rounded-full bg-emerald-600/5 blur-3xl"
        animate={{
          scale: [1, 1.1, 1],
          opacity: [0.2, 0.4, 0.2],
        }}
        transition={{ duration: 6, repeat: Infinity, ease: 'easeInOut' }}
      />

      {/* Terminal background effect */}
      <div className="absolute right-0 top-0 w-full md:w-1/2 h-full opacity-[0.07] pointer-events-none overflow-hidden p-8">
        <div className="font-mono text-xs text-emerald-400 space-y-1">
          {terminalLines.map((line, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 1 + i * 0.3, duration: 0.5 }}
            >
              {line}
            </motion.div>
          ))}
        </div>
      </div>

      {/* Content */}
      <div className="relative z-10 max-w-5xl mx-auto px-4 sm:px-6 text-center">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
        >
          {/* Icon */}
          <motion.div
            className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 mb-6"
            whileHover={{ scale: 1.05, rotate: 5 }}
            transition={{ type: 'spring', stiffness: 300 }}
          >
            <Monitor className="w-8 h-8 text-emerald-400" />
          </motion.div>

          {/* Title */}
          <h1 className="text-4xl sm:text-5xl md:text-7xl font-bold tracking-tight mb-4">
            <span className="text-white">Codex Desktop</span>
            <br />
            <span className="bg-gradient-to-r from-emerald-400 to-teal-300 bg-clip-text text-transparent">
              for Windows
            </span>
          </h1>

          {/* Subtitle */}
          <p className="text-lg sm:text-xl text-gray-400 max-w-2xl mx-auto mb-8">
            Run OpenAI&apos;s Codex Desktop on Windows — unofficial community port
          </p>

          {/* Badges */}
          <div className="flex flex-wrap items-center justify-center gap-2 sm:gap-3 mb-10">
            {['Windows', 'Electron', 'Open Source'].map((badge) => (
              <Badge
                key={badge}
                variant="outline"
                className="px-3 sm:px-4 py-1.5 text-sm border-emerald-500/30 text-emerald-300 bg-emerald-500/5 hover:bg-emerald-500/10 transition-colors"
              >
                {badge === 'Windows' && <Monitor className="w-3.5 h-3.5 mr-1.5" />}
                {badge === 'Electron' && <Terminal className="w-3.5 h-3.5 mr-1.5" />}
                {badge}
              </Badge>
            ))}
          </div>

          {/* CTA Buttons */}
          <div className="flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-4">
            <Button
              size="lg"
              className="bg-emerald-600 hover:bg-emerald-500 text-white px-6 sm:px-8 py-5 sm:py-6 text-base sm:text-lg rounded-xl shadow-lg shadow-emerald-600/20 group"
              onClick={scrollToSetup}
            >
              Get Started
              <ChevronRight className="w-5 h-5 ml-1 group-hover:translate-x-0.5 transition-transform" />
            </Button>
            <Button
              size="lg"
              variant="outline"
              className="border-gray-600 text-gray-300 hover:text-white hover:border-gray-400 px-6 sm:px-8 py-5 sm:py-6 text-base sm:text-lg rounded-xl group"
              asChild
            >
              <a
                href="https://github.com/ilysenko/codex-desktop-linux"
                target="_blank"
                rel="noopener noreferrer"
              >
                <Github className="w-5 h-5 mr-2" />
                View on GitHub
              </a>
            </Button>
          </div>
        </motion.div>
      </div>

      {/* Bottom gradient fade */}
      <div className="absolute bottom-0 left-0 right-0 h-32 bg-gradient-to-t from-gray-950 to-transparent" />
    </section>
  );
}
