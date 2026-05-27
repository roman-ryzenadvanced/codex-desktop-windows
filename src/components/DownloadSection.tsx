'use client';

import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Download, FileArchive, Cpu, FileCode } from 'lucide-react';

interface DownloadItem {
  icon: React.ElementType;
  title: string;
  description: string;
  size: string;
  color: string;
}

const downloads: DownloadItem[] = [
  {
    icon: FileArchive,
    title: 'Complete Toolkit',
    description: 'Full project including installer, scripts, launcher source, and packaging',
    size: '~2.4 MB',
    color: 'text-emerald-400',
  },
  {
    icon: Cpu,
    title: 'Windows Launcher (.exe)',
    description: 'Pre-compiled Rust launcher executable for Windows x64',
    size: '~1.8 MB',
    color: 'text-teal-400',
  },
  {
    icon: FileCode,
    title: 'NSIS Installer Script',
    description: 'NSIS installer configuration for creating a Windows setup wizard',
    size: '~4 KB',
    color: 'text-cyan-400',
  },
];

export default function DownloadSection() {
  return (
    <section id="download" className="py-20 sm:py-28 bg-gray-950/50">
      <div className="max-w-4xl mx-auto px-4 sm:px-6">
        <motion.div
          className="text-center mb-14"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-100px' }}
          transition={{ duration: 0.6 }}
        >
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-4">
            Downloads
          </h2>
          <p className="text-gray-400 text-lg max-w-2xl mx-auto">
            Get the files you need to install or contribute to Codex Desktop for Windows
          </p>
        </motion.div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
          {downloads.map((item, i) => (
            <motion.div
              key={item.title}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.1, duration: 0.5 }}
            >
              <Card className="bg-gray-900/60 border-gray-800 hover:border-emerald-500/30 transition-all duration-300 group h-full">
                <CardContent className="p-6 flex flex-col items-center text-center">
                  <div className="w-14 h-14 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center mb-4 group-hover:bg-emerald-500/20 transition-colors">
                    <item.icon className={`w-7 h-7 ${item.color}`} />
                  </div>
                  <h3 className="font-semibold text-white mb-2">{item.title}</h3>
                  <p className="text-gray-500 text-sm mb-4 flex-1">{item.description}</p>
                  <div className="text-xs text-gray-600 mb-4 font-mono">{item.size}</div>
                  <Button
                    className="w-full bg-emerald-600 hover:bg-emerald-500 text-white group-hover:shadow-lg group-hover:shadow-emerald-600/10 transition-all"
                    onClick={() => {
                      // In a real app, this would trigger a download
                      window.open(
                        'https://github.com/ilysenko/codex-desktop-linux',
                        '_blank'
                      );
                    }}
                  >
                    <Download className="w-4 h-4 mr-2" />
                    Download
                  </Button>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
