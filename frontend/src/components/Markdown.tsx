import ReactMarkdown from "react-markdown";

// Minimal styled markdown (no typography plugin) — strips the `node` prop that
// react-markdown passes so it isn't forwarded onto DOM elements.
export function Markdown({ children }: { children: string }) {
  return (
    <ReactMarkdown
      components={{
        h1: ({ node, ...p }) => (
          <h3 className="mb-1 mt-3 text-sm font-semibold uppercase tracking-wide text-muted" {...p} />
        ),
        h2: ({ node, ...p }) => (
          <h3 className="mb-1 mt-3 text-sm font-semibold uppercase tracking-wide text-muted" {...p} />
        ),
        h3: ({ node, ...p }) => <h4 className="mb-1 mt-2 font-medium" {...p} />,
        p: ({ node, ...p }) => <p className="mb-2 text-sm leading-relaxed" {...p} />,
        ul: ({ node, ...p }) => <ul className="mb-2 ml-5 list-disc text-sm" {...p} />,
        ol: ({ node, ...p }) => <ol className="mb-2 ml-5 list-decimal text-sm" {...p} />,
        li: ({ node, ...p }) => <li className="mb-1" {...p} />,
        strong: ({ node, ...p }) => <strong className="font-semibold" {...p} />,
        em: ({ node, ...p }) => <em className="italic text-muted" {...p} />,
        a: ({ node, ...p }) => <a className="text-accent" target="_blank" rel="noreferrer" {...p} />,
      }}
    >
      {children}
    </ReactMarkdown>
  );
}
