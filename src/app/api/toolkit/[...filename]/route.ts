import { NextRequest, NextResponse } from "next/server";
import { readFile } from "fs/promises";
import { join } from "path";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ filename: string[] }> }
) {
  const { filename } = await params;

  // Reconstruct the file path from the catch-all segments
  const decodedFilename = filename
    .map((segment) => decodeURIComponent(segment))
    .join("/");

  // Security: only allow files within the toolkit directory
  const toolkitDir = join(process.cwd(), "public", "toolkit");
  const filePath = join(toolkitDir, decodedFilename);

  // Ensure the resolved path is within the toolkit directory
  if (!filePath.startsWith(toolkitDir)) {
    return NextResponse.json({ error: "Invalid path" }, { status: 400 });
  }

  try {
    const content = await readFile(filePath, "utf-8");

    return new NextResponse(content, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "public, max-age=3600",
      },
    });
  } catch {
    return NextResponse.json(
      { error: "File not found", path: decodedFilename },
      { status: 404 }
    );
  }
}
