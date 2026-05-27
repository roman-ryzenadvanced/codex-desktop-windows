'use client';

import { useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Card, CardContent } from '@/components/ui/card';
import { ScrollArea } from '@/components/ui/scroll-area';
import {
  ChevronRight,
  ChevronDown,
  File,
  Folder,
  FolderOpen,
  Loader2,
} from 'lucide-react';
import CodeBlock from './CodeBlock';

interface FileTreeNode {
  name: string;
  type: 'file' | 'folder';
  children?: FileTreeNode[];
  path: string;
  comment?: string;
  language?: string;
}

const fileTree: FileTreeNode[] = [
  {
    name: 'codex-desktop-windows/',
    type: 'folder',
    path: '',
    children: [
      {
        name: 'install.ps1',
        type: 'file',
        path: 'install.ps1',
        comment: 'Main PowerShell installer',
        language: 'powershell',
      },
      {
        name: 'Cargo.toml',
        type: 'file',
        path: 'Cargo.toml',
        comment: 'Rust workspace root',
        language: 'toml',
      },
      {
        name: 'launcher/',
        type: 'folder',
        path: 'launcher',
        children: [
          {
            name: 'start.ps1.template',
            type: 'file',
            path: 'launcher/start.ps1.template',
            comment: 'Windows launcher template',
            language: 'powershell',
          },
          {
            name: 'webview-server.py',
            type: 'file',
            path: 'launcher/webview-server.py',
            comment: 'Webview HTTP server',
            language: 'python',
          },
          {
            name: 'src/',
            type: 'folder',
            path: 'launcher/src',
            children: [
              {
                name: 'main.rs',
                type: 'file',
                path: 'launcher/src/main.rs',
                comment: 'Rust .exe launcher',
                language: 'rust',
              },
            ],
          },
        ],
      },
      {
        name: 'scripts/',
        type: 'folder',
        path: 'scripts',
        children: [
          {
            name: 'patch-windows.js',
            type: 'file',
            path: 'scripts/patch-windows.js',
            comment: 'ASAR patch system',
            language: 'javascript',
          },
          {
            name: 'lib/',
            type: 'folder',
            path: 'scripts/lib',
            children: [
              {
                name: 'Dmg-Extractor.ps1',
                type: 'file',
                path: 'scripts/lib/Dmg-Extractor.ps1',
                language: 'powershell',
              },
              {
                name: 'Electron-Downloader.ps1',
                type: 'file',
                path: 'scripts/lib/Electron-Downloader.ps1',
                language: 'powershell',
              },
              {
                name: 'Native-Modules.ps1',
                type: 'file',
                path: 'scripts/lib/Native-Modules.ps1',
                language: 'powershell',
              },
              {
                name: 'Node-Runtime.ps1',
                type: 'file',
                path: 'scripts/lib/Node-Runtime.ps1',
                language: 'powershell',
              },
              {
                name: 'Plugin-Manager.ps1',
                type: 'file',
                path: 'scripts/lib/Plugin-Manager.ps1',
                language: 'powershell',
              },
            ],
          },
        ],
      },
      {
        name: 'packaging/',
        type: 'folder',
        path: 'packaging',
        children: [
          {
            name: 'codex-desktop.nsi',
            type: 'file',
            path: 'packaging/codex-desktop.nsi',
            comment: 'NSIS installer',
            language: 'nsis',
          },
          {
            name: 'codex-update-manager.xml',
            type: 'file',
            path: 'packaging/codex-update-manager.xml',
            language: 'xml',
          },
        ],
      },
      {
        name: 'updater/',
        type: 'folder',
        path: 'updater',
        children: [
          {
            name: 'Cargo.toml',
            type: 'file',
            path: 'updater/Cargo.toml',
            language: 'toml',
          },
          {
            name: 'src/',
            type: 'folder',
            path: 'updater/src',
            children: [
              {
                name: 'main.rs',
                type: 'file',
                path: 'updater/src/main.rs',
                comment: 'Windows updater',
                language: 'rust',
              },
            ],
          },
        ],
      },
      {
        name: 'README.md',
        type: 'file',
        path: 'README.md',
        language: 'markdown',
      },
    ],
  },
];

function FileTreeItem({
  node,
  depth,
  expanded,
  onToggle,
  selectedPath,
  onSelect,
}: {
  node: FileTreeNode;
  depth: number;
  expanded: Set<string>;
  onToggle: (path: string) => void;
  selectedPath: string | null;
  onSelect: (node: FileTreeNode) => void;
}) {
  const isExpanded = expanded.has(node.path);
  const isSelected = selectedPath === node.path;
  const isFolder = node.type === 'folder';

  return (
    <div>
      <button
        className={`w-full flex items-center gap-1.5 px-2 py-1.5 rounded-md text-sm transition-colors text-left ${
          isSelected
            ? 'bg-emerald-500/10 text-emerald-300'
            : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800/50'
        }`}
        style={{ paddingLeft: `${depth * 16 + 8}px` }}
        onClick={() => {
          if (isFolder) {
            onToggle(node.path);
          } else {
            onSelect(node);
          }
        }}
      >
        {isFolder ? (
          <>
            {isExpanded ? (
              <ChevronDown className="w-3.5 h-3.5 flex-shrink-0 text-gray-500" />
            ) : (
              <ChevronRight className="w-3.5 h-3.5 flex-shrink-0 text-gray-500" />
            )}
            {isExpanded ? (
              <FolderOpen className="w-4 h-4 flex-shrink-0 text-amber-400/70" />
            ) : (
              <Folder className="w-4 h-4 flex-shrink-0 text-amber-400/50" />
            )}
          </>
        ) : (
          <>
            <span className="w-3.5" />
            <File className="w-4 h-4 flex-shrink-0 text-gray-500" />
          </>
        )}
        <span className="truncate">{node.name}</span>
        {!isFolder && node.comment && (
          <span className="ml-auto text-xs text-gray-600 truncate hidden sm:inline">
            {node.comment}
          </span>
        )}
      </button>

      {/* Children */}
      <AnimatePresence>
        {isFolder && isExpanded && node.children && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="overflow-hidden"
          >
            {node.children.map((child) => (
              <FileTreeItem
                key={child.path}
                node={child}
                depth={depth + 1}
                expanded={expanded}
                onToggle={onToggle}
                selectedPath={selectedPath}
                onSelect={onSelect}
              />
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

export default function FileExplorerSection() {
  const [expanded, setExpanded] = useState<Set<string>>(
    new Set(['', 'launcher', 'launcher/src', 'scripts', 'scripts/lib', 'packaging', 'updater', 'updater/src'])
  );
  const [selectedPath, setSelectedPath] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<{
    name: string;
    path: string;
    language: string;
  } | null>(null);
  const [fileContent, setFileContent] = useState<string>('');
  const [loading, setLoading] = useState(false);

  const onToggle = useCallback((path: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(path)) {
        next.delete(path);
      } else {
        next.add(path);
      }
      return next;
    });
  }, []);

  const onSelect = useCallback(async (node: FileTreeNode) => {
    setSelectedPath(node.path);
    setSelectedFile({ name: node.name, path: node.path, language: node.language || 'text' });
    setLoading(true);

    try {
      const pathSegments = node.path.split('/').map(encodeURIComponent).join('/');
      const res = await fetch(`/api/toolkit/${pathSegments}`);
      if (res.ok) {
        const text = await res.text();
        setFileContent(text);
      } else {
        setFileContent('// File not found or unable to read');
      }
    } catch {
      setFileContent('// Error loading file');
    } finally {
      setLoading(false);
    }
  }, []);

  return (
    <section id="file-explorer" className="py-20 sm:py-28 bg-gray-950/50">
      <div className="max-w-6xl mx-auto px-4 sm:px-6">
        <motion.div
          className="text-center mb-14"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-100px' }}
          transition={{ duration: 0.6 }}
        >
          <h2 className="text-3xl sm:text-4xl font-bold text-white mb-4">
            Project Explorer
          </h2>
          <p className="text-gray-400 text-lg max-w-2xl mx-auto">
            Browse the project structure and view source code
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-50px' }}
          transition={{ duration: 0.6 }}
        >
          <Card className="bg-gray-900/60 border-gray-800 overflow-hidden">
            <div className="flex flex-col lg:flex-row min-h-[500px]">
              {/* File tree */}
              <div className="lg:w-80 flex-shrink-0 border-b lg:border-b-0 lg:border-r border-gray-800">
                <div className="px-4 py-3 border-b border-gray-800 bg-gray-900/40">
                  <h3 className="text-sm font-semibold text-gray-300 flex items-center gap-2">
                    <Folder className="w-4 h-4 text-amber-400/70" />
                    File Tree
                  </h3>
                </div>
                <ScrollArea className="h-[400px] lg:h-auto lg:max-h-[600px]">
                  <div className="p-2">
                    {fileTree.map((node) => (
                      <FileTreeItem
                        key={node.path}
                        node={node}
                        depth={0}
                        expanded={expanded}
                        onToggle={onToggle}
                        selectedPath={selectedPath}
                        onSelect={onSelect}
                      />
                    ))}
                  </div>
                </ScrollArea>
              </div>

              {/* Code viewer */}
              <div className="flex-1 min-w-0">
                <div className="px-4 py-3 border-b border-gray-800 bg-gray-900/40 flex items-center justify-between">
                  <h3 className="text-sm font-semibold text-gray-300 flex items-center gap-2">
                    <File className="w-4 h-4 text-gray-500" />
                    {selectedFile ? selectedFile.name : 'Select a file to view'}
                  </h3>
                  {selectedFile && (
                    <span className="text-xs text-gray-600 font-mono">
                      {selectedFile.path}
                    </span>
                  )}
                </div>
                <div className="p-3">
                  {loading ? (
                    <div className="flex items-center justify-center h-64 text-gray-500">
                      <Loader2 className="w-6 h-6 animate-spin mr-2" />
                      <span>Loading...</span>
                    </div>
                  ) : selectedFile ? (
                    <CodeBlock
                      code={fileContent}
                      language={selectedFile.language}
                      filename={selectedFile.name}
                    />
                  ) : (
                    <div className="flex flex-col items-center justify-center h-64 text-gray-500">
                      <Folder className="w-12 h-12 mb-3 opacity-30" />
                      <p className="text-sm">Click a file in the tree to view its contents</p>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </Card>
        </motion.div>
      </div>
    </section>
  );
}
