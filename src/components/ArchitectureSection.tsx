'use client';

import { motion } from 'framer-motion';
import { Card, CardContent } from '@/components/ui/card';
import { Download, Archive, Wrench, Box, Cog, Rocket, Play } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

interface PipelineStep {
  icon: LucideIcon;
  label: string;
  description: string;
  color: string;
}

const pipeline: PipelineStep[] = [
  {
    icon: Download,
    label: 'DMG Download',
    description: 'Downloads the macOS Codex Desktop DMG',
    color: 'text-blue-400',
  },
  {
    icon: Archive,
    label: 'Extract',
    description: 'Extracts the app bundle from DMG',
    color: 'text-purple-400',
  },
  {
    icon: Wrench,
    label: 'Patch ASAR',
    description: 'Patches ASAR for Windows compat',
    color: 'text-amber-400',
  },
  {
    icon: Box,
    label: 'Download Electron',
    description: 'Gets Windows Electron runtime',
    color: 'text-cyan-400',
  },
  {
    icon: Cog,
    label: 'Rebuild Natives',
    description: 'Rebuilds native Node modules',
    color: 'text-rose-400',
  },
  {
    icon: Rocket,
    label: 'Install',
    description: 'Installs plugins & registers URL handler',
    color: 'text-emerald-400',
  },
  {
    icon: Play,
    label: 'Launch',
    description: 'Starts via Rust .exe launcher',
    color: 'text-teal-400',
  },
];

export default function ArchitectureSection() {
  return (
    <section id="architecture" className="py-20 sm:py-28 bg-gray-950/50">
      <div className="max-w-6xl mx-auto px-4 sm:px-6">
        <motion.div
          className="text-center mb-14"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-100px' }}
          transition={{ duration: 0.6 }}
        >
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-4">
            Conversion Pipeline
          </h2>
          <p className="text-gray-400 text-lg max-w-2xl mx-auto">
            From macOS DMG to native Windows application in seven steps
          </p>
        </motion.div>

        {/* Pipeline flow */}
        <div className="relative">
          {/* Desktop: horizontal flow */}
          <div className="hidden lg:block">
            <div className="flex items-center justify-between gap-2">
              {pipeline.map((step, i) => (
                <motion.div
                  key={step.label}
                  className="flex-1 flex items-center"
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ delay: i * 0.12, duration: 0.5 }}
                >
                  <Card className="bg-gray-900/60 border-gray-800 hover:border-emerald-500/30 transition-all duration-300 group flex-1">
                    <CardContent className="p-4 text-center">
                      <div className="inline-flex items-center justify-center w-10 h-10 rounded-lg bg-emerald-500/10 border border-emerald-500/20 mb-3 group-hover:bg-emerald-500/20 transition-colors">
                        <step.icon className={`w-5 h-5 ${step.color}`} />
                      </div>
                      <div className="text-xs font-mono text-emerald-500 mb-1">
                        Step {i + 1}
                      </div>
                      <h4 className="font-semibold text-white text-sm mb-1">
                        {step.label}
                      </h4>
                      <p className="text-gray-500 text-xs leading-relaxed">
                        {step.description}
                      </p>
                    </CardContent>
                  </Card>
                  {i < pipeline.length - 1 && (
                    <div className="flex-shrink-0 px-1">
                      <motion.div
                        className="w-6 h-0.5 bg-gradient-to-r from-emerald-500/40 to-emerald-500/20"
                        initial={{ scaleX: 0 }}
                        whileInView={{ scaleX: 1 }}
                        viewport={{ once: true }}
                        transition={{ delay: i * 0.12 + 0.3, duration: 0.3 }}
                      />
                    </div>
                  )}
                </motion.div>
              ))}
            </div>
          </div>

          {/* Mobile/Tablet: vertical flow */}
          <div className="lg:hidden space-y-3">
            {pipeline.map((step, i) => (
              <motion.div
                key={step.label}
                initial={{ opacity: 0, x: -20 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.08, duration: 0.4 }}
              >
                <Card className="bg-gray-900/60 border-gray-800 hover:border-emerald-500/30 transition-all duration-300 group">
                  <CardContent className="p-4 flex items-center gap-4">
                    <div className="flex-shrink-0 flex items-center justify-center w-10 h-10 rounded-lg bg-emerald-500/10 border border-emerald-500/20 group-hover:bg-emerald-500/20 transition-colors">
                      <step.icon className={`w-5 h-5 ${step.color}`} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <span className="text-xs font-mono text-emerald-500">
                          Step {i + 1}
                        </span>
                        <h4 className="font-semibold text-white text-sm">
                          {step.label}
                        </h4>
                      </div>
                      <p className="text-gray-500 text-xs">{step.description}</p>
                    </div>
                    {i < pipeline.length - 1 && (
                      <div className="absolute left-[1.75rem] top-full w-0.5 h-3 bg-emerald-500/20" />
                    )}
                  </CardContent>
                </Card>
              </motion.div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
