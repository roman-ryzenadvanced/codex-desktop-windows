'use client';

import { useState } from 'react';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';
import { Check, Copy } from 'lucide-react';

interface CodeBlockProps {
  code: string;
  language?: string;
  filename?: string;
  showCopy?: boolean;
}

const customStyle: React.CSSProperties = {
  margin: 0,
  padding: '1rem',
  background: 'transparent',
  fontSize: '0.8125rem',
  lineHeight: '1.6',
};

export default function CodeBlock({
  code,
  language = 'text',
  filename,
  showCopy = true,
}: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="rounded-lg bg-[#1e1e1e] border border-gray-800 overflow-hidden">
      {/* Header bar */}
      {(filename || showCopy) && (
        <div className="flex items-center justify-between px-4 py-2 bg-[#252526] border-b border-gray-800">
          <div className="flex items-center gap-2">
            <div className="flex gap-1.5">
              <div className="w-3 h-3 rounded-full bg-red-500/70" />
              <div className="w-3 h-3 rounded-full bg-yellow-500/70" />
              <div className="w-3 h-3 rounded-full bg-green-500/70" />
            </div>
            {filename && (
              <span className="ml-3 text-xs text-gray-400 font-mono">{filename}</span>
            )}
          </div>
          {showCopy && (
            <button
              onClick={handleCopy}
              className="flex items-center gap-1.5 px-2 py-1 rounded text-xs text-gray-400 hover:text-white hover:bg-gray-700 transition-colors"
            >
              {copied ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-400" />
                  <span className="text-emerald-400">Copied</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5" />
                  <span>Copy</span>
                </>
              )}
            </button>
          )}
        </div>
      )}

      {/* Code content */}
      <div className="overflow-x-auto max-h-[500px] overflow-y-auto">
        <SyntaxHighlighter
          language={language}
          style={vscDarkPlus}
          customStyle={customStyle}
          showLineNumbers={code.split('\n').length > 3}
          lineNumberStyle={{ minWidth: '2.5em', paddingRight: '1em', color: '#555' }}
        >
          {code}
        </SyntaxHighlighter>
      </div>
    </div>
  );
}
