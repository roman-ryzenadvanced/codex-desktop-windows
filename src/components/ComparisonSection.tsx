'use client';

import { motion } from 'framer-motion';
import { Card, CardContent } from '@/components/ui/card';

interface ComparisonRow {
  feature: string;
  linux: string;
  windows: string;
}

const comparisons: ComparisonRow[] = [
  { feature: 'Installer', linux: 'install.sh', windows: 'install.ps1' },
  { feature: 'Launcher', linux: 'start.sh', windows: 'start.ps1 + .exe' },
  { feature: 'Packaging', linux: '.deb/.rpm/pacman', windows: 'NSIS .exe' },
  { feature: 'Auto-update', linux: 'systemd service', windows: 'Task Scheduler' },
  { feature: 'Computer Use', linux: 'AT-SPI/Wayland', windows: 'Windows UI Automation' },
  { feature: 'Single Instance', linux: 'Unix socket', windows: 'Named Mutex' },
  { feature: 'URL Handler', linux: 'xdg-mime', windows: 'Registry' },
];

export default function ComparisonSection() {
  return (
    <section id="comparison" className="py-20 sm:py-28 bg-gray-950">
      <div className="max-w-4xl mx-auto px-4 sm:px-6">
        <motion.div
          className="text-center mb-14"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-100px' }}
          transition={{ duration: 0.6 }}
        >
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-4">
            Linux vs Windows
          </h2>
          <p className="text-gray-400 text-lg max-w-2xl mx-auto">
            How the Windows port adapts each subsystem from the Linux version
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-50px' }}
          transition={{ duration: 0.6 }}
        >
          <Card className="bg-gray-900/60 border-gray-800 overflow-hidden">
            <CardContent className="p-0">
              {/* Header */}
              <div className="grid grid-cols-3 border-b border-gray-800">
                <div className="px-4 sm:px-6 py-3.5 bg-gray-900/40">
                  <span className="text-sm font-semibold text-gray-400">Feature</span>
                </div>
                <div className="px-4 sm:px-6 py-3.5 bg-gray-900/40 border-l border-gray-800">
                  <span className="text-sm font-semibold text-amber-400">🐧 Linux</span>
                </div>
                <div className="px-4 sm:px-6 py-3.5 bg-gray-900/40 border-l border-gray-800">
                  <span className="text-sm font-semibold text-emerald-400">🪟 Windows</span>
                </div>
              </div>

              {/* Rows */}
              {comparisons.map((row, i) => (
                <motion.div
                  key={row.feature}
                  className={`grid grid-cols-3 ${
                    i < comparisons.length - 1 ? 'border-b border-gray-800/50' : ''
                  }`}
                  initial={{ opacity: 0, x: -10 }}
                  whileInView={{ opacity: 1, x: 0 }}
                  viewport={{ once: true }}
                  transition={{ delay: i * 0.06, duration: 0.4 }}
                >
                  <div className="px-4 sm:px-6 py-3.5">
                    <span className="text-sm font-medium text-white">{row.feature}</span>
                  </div>
                  <div className="px-4 sm:px-6 py-3.5 border-l border-gray-800/50">
                    <code className="text-xs sm:text-sm text-amber-300/80 bg-amber-500/5 px-1.5 py-0.5 rounded">
                      {row.linux}
                    </code>
                  </div>
                  <div className="px-4 sm:px-6 py-3.5 border-l border-gray-800/50">
                    <code className="text-xs sm:text-sm text-emerald-300/80 bg-emerald-500/5 px-1.5 py-0.5 rounded">
                      {row.windows}
                    </code>
                  </div>
                </motion.div>
              ))}
            </CardContent>
          </Card>
        </motion.div>
      </div>
    </section>
  );
}
