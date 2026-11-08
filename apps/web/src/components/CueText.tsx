import { tokenizeCue } from "../lib/focusWords";

type Props = {
  text: string;
  level?: string;
  knownWords?: Set<string>;
  highlight?: boolean;
  onWordClick?: (word: string) => void;
};

export function CueText({
  text,
  level = "A2",
  knownWords,
  highlight = true,
  onWordClick,
}: Props) {
  if (!highlight) {
    return <>{text}</>;
  }
  const pieces = tokenizeCue(text, { level, knownWords });
  return (
    <>
      {pieces.map((piece, i) => {
        if (!piece.focus && !piece.known) {
          return <span key={i}>{piece.text}</span>;
        }
        const cls = piece.known ? "word-known" : "word-focus";
        if (!onWordClick || /^\s+$/.test(piece.text)) {
          return (
            <span key={i} className={cls}>
              {piece.text}
            </span>
          );
        }
        return (
          <button
            key={i}
            type="button"
            className={`word-btn ${cls}`}
            title={piece.known ? "已在生词本" : "点击加入生词本"}
            onClick={(e) => {
              e.stopPropagation();
              const w = piece.text.replace(/^[^a-zA-Z']+|[^a-zA-Z']+$/g, "");
              if (w) onWordClick(w);
            }}
          >
            {piece.text}
          </button>
        );
      })}
    </>
  );
}
