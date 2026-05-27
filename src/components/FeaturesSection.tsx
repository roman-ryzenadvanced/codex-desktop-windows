'use client';

import { motion } from 'framer-motion';
import { Card, CardContent } from '@/components/ui/card';
import { Monitor, RefreshCw, Plug, Shield, Package, Globe } from 'lucide-react';

const features = [
  {
    icon: Monitor,
    title: 'Windows Native',
    description: 'Runs as a native Windows application with .exe launcher built in Rust',
    emoji: '🖥️',
  },
  {
    icon: RefreshCw,
    title: 'Auto-Update',
    description: 'Automatic updates with rollback support via Windows Task Scheduler',
    emoji: '🔄',
  },
  {
    icon: Plug,
    title: 'Plugin System',
    description: 'MCP plugin support — Computer Use, Read Aloud, Browser Use',
    emoji: '🔌',
  },
  {
    icon: Shield,
    title: 'Single Instance',
    description: 'Mutex-based single instance enforcement prevents duplicate windows',
    emoji: '🛡️',
  },
  {
    icon: Package,
    title: 'Easy Install',
    description: 'PowerShell installer with one-command setup and NSIS packaging',
    emoji: '📦',
  },
  {
    icon: Globe,
    title: 'Webview Server',
    description: 'Local HTTP server for serving webview assets with CORS support',
    emoji: '🌐',
  },
];

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.1 },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.5 } },
};

export default function FeaturesSection() {
  return (
    <section id="features" className="py-20 sm:py-28 bg-gray-950">
      <div className="max-w-6xl mx-auto px-4 sm:px-6">
        <motion.div
          className="text-center mb-14"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-100px' }}
          transition={{ duration: 0.6 }}
        >
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-4">
            Powerful Features
          </h2>
          <p className="text-gray-400 text-lg max-w-2xl mx-auto">
            Everything you need to run Codex Desktop seamlessly on Windows
          </p>
        </motion.div>

        <motion.div
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6"
          variants={containerVariants}
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: '-50px' }}
        >
          {features.map((feature) => (
            <motion.div key={feature.title} variants={itemVariants}>
              <Card className="bg-gray-900/50 border-gray-800 hover:border-emerald-500/30 transition-all duration-300 group h-full">
                <CardContent className="p-6">
                  <div className="flex items-start gap-4">
                    <div className="flex-shrink-0 w-12 h-12 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center group-hover:bg-emerald-500/20 transition-colors">
                      <feature.icon className="w-6 h-6 text-emerald-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <h3 className="text-lg font-semibold text-white mb-1.5 group-hover:text-emerald-300 transition-colors">
                        {feature.title}
                      </h3>
                      <p className="text-gray-400 text-sm leading-relaxed">
                        {feature.description}
                      </p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
