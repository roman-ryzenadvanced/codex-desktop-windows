'use client';

import { Github, Heart, ExternalLink } from 'lucide-react';

const links = [
  { label: 'GitHub', href: 'https://github.com/ilysenko/codex-desktop-linux', icon: Github },
  { label: 'OpenAI Codex', href: 'https://github.com/openai/codex', icon: ExternalLink },
];

export default function Footer() {
  return (
    <footer className="bg-gray-950 border-t border-gray-800/50 mt-auto">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8">
        <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
          {/* Left: Branding */}
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center">
              <span className="text-emerald-400 text-sm font-bold">C</span>
            </div>
            <div>
              <p className="text-sm font-medium text-gray-300">
                Codex Desktop for Windows
              </p>
              <p className="text-xs text-gray-600">
                Unofficial community port
              </p>
            </div>
          </div>

          {/* Center: Links */}
          <div className="flex items-center gap-4 sm:gap-6">
            {links.map((link) => (
              <a
                key={link.label}
                href={link.href}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1.5 text-sm text-gray-500 hover:text-emerald-400 transition-colors"
              >
                <link.icon className="w-4 h-4" />
                <span>{link.label}</span>
              </a>
            ))}
          </div>

          {/* Right: Credits */}
          <div className="flex items-center gap-1.5 text-xs text-gray-600">
            <span>Made with</span>
            <Heart className="w-3 h-3 text-red-400/60 fill-red-400/60" />
            <span>by the community</span>
          </div>
        </div>

        {/* Bottom separator and copyright */}
        <div className="mt-6 pt-4 border-t border-gray-800/30 text-center">
          <p className="text-xs text-gray-700">
            This project is not affiliated with OpenAI. Codex Desktop is a trademark of OpenAI.
          </p>
        </div>
      </div>
    </footer>
  );
}
