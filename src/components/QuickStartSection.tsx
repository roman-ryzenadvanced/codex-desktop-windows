'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import { Card, CardContent } from '@/components/ui/card';
import { Check, Copy, Terminal as TerminalIcon } from 'lucide-react';

interface Step {
  number: number;
  title: string;
  code: string;
  comment: string;
}

const steps: Step[] = [
  {
    number: 1,
    title: 'Clone the repository',
    code: 'git clone https://github.com/ilysenko/codex-desktop-linux.git\ncd codex-desktop-linux',
    comment: '# 1. Clone the repository',
  },
  {
    number: 2,
    title: 'Run the installer',
    code: '.\\install.ps1',
    comment: '# 2. Run the installer',
  },
  {
    number: 3,
    title: 'Launch Codex Desktop',
    code: '.\\start.ps1',
    comment: '# 3. Launch Codex Desktop',
  },
];

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      onClick={handleCopy}
      className="absolute top-3 right-3 p-1.5 rounded-md bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-white transition-colors"
      title="Copy to clipboard"
    >
      {copied ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
    </button>
  );
}

export default function QuickStartSection() {
  return (
    <section id="quick-start" className="py-20 sm:py-28 bg-gray-950">
      <div className="max-w-4xl mx-auto px-4 sm:px-6">
        <motion.div
          className="text-center mb-14"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-100px' }}
          transition={{ duration: 0.6 }}
        >
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-4">
            Quick Start
          </h2>
          <p className="text-gray-400 text-lg max-w-2xl mx-auto">
            Get Codex Desktop running on Windows in three simple steps
          </p>
        </motion.div>

        <div className="space-y-4 sm:space-y-6">
          {steps.map((step, i) => (
            <motion.div
              key={step.number}
              initial={{ opacity: 0, x: -20 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.15, duration: 0.5 }}
            >
              <Card className="bg-gray-900/60 border-gray-800 hover:border-emerald-500/30 transition-all duration-300 group overflow-hidden">
                <CardContent className="p-0">
                  {/* Step header */}
                  <div className="flex items-center gap-3 px-5 py-3 border-b border-gray-800">
                    <div className="flex items-center justify-center w-7 h-7 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-sm font-bold">
                      {step.number}
                    </div>
                    <span className="text-white font-medium text-sm">{step.title}</span>
                  </div>

                  {/* Code block */}
                  <div className="relative">
                    <div className="px-5 py-4 font-mono text-sm overflow-x-auto">
                      <span className="text-gray-500 select-none">{step.comment}</span>
                      <br />
                      {step.code.split('\n').map((line, li) => (
                        <span key={li}>
                          {line.startsWith('#') ? (
                            <span className="text-gray-500">{line}</span>
                          ) : (
                            <span className="text-emerald-300">{line}</span>
                          )}
                          {li < step.code.split('\n').length - 1 && <br />}
                        </span>
                      ))}
                    </div>
                    <CopyButton text={`${step.comment}\n${step.code}`} />
                  </div>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>

        {/* Terminal prompt decoration */}
        <motion.div
          className="mt-8 flex items-center justify-center gap-2 text-gray-500"
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ delay: 0.6, duration: 0.5 }}
        >
          <TerminalIcon className="w-4 h-4" />
          <span className="text-sm">PowerShell 7+ recommended</span>
        </motion.div>
      </div>
    </section>
  );
}
