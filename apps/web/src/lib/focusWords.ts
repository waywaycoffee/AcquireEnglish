/** Common A1–A2 words treated as “easy”; longer / rarer tokens get focus underline. */
const EASY_WORDS = new Set(
  `
a about above across after again against all almost along already also always am
an and another any anyone anything are around as ask at away back bad be because
been before begin behind being believe best better between big both bring but by
call can cannot come could day did do does doing done down during each early
easy eat end enough even ever every everyone everything example eye face far
fast feel few find first for from get give go going gone good got great had
hand happen happy hard has have he head hear help her here high him his home
hope hot how however i if important in into is it its just keep kind know large
last late later learn leave left let life like little live long look lot love
low make man many may me mean meet might mind more most much must my name near
need never new next night no not nothing now number of off often ok okay old
on once one only open or other our out over own part people place play please
point put quite rather read ready real really right room run said same say see
seem she should show side since small so some someone something sometimes soon
start still stop such sure take talk tell than that the their them then there
these they thing think this those though through time to today together too
try turn under until up us use used very want was watch water way we well went
were what when where which while who why will with without word work world would
write year yes you young your
able across actually add afraid ago agree air almost alone already although
among answer area around arrive ask baby bad bag ball bank bed before begin
behind believe below between bike bird black blue body book born both box boy
bread break breakfast bring brother brown build bus business buy cake call car
card care carry case cat catch center change check child children choose city
class clean clear close clothes cloud coffee cold color come company complete
computer continue cook cool copy corner cost country course cover create cross
cup cut dad dance dark date daughter day dead deal decide deep desk different
dinner dirty do doctor dog door down draw dream dress drink drive drop dry
during early earth east easy eat egg eight either else end enjoy enough enter
evening ever every everyone everything exam example excuse exercise expect
explain eye face fact fall family far farm fast father feel few field fifteen
fifty fill film final finally find fine finish fire first fish five floor fly
follow food foot for forget form forty four free friend from front fruit full
fun future game garden get girl give glass go goal gold good goodbye government
grass green ground group grow guess guy hair half hall hand happen happy hard
hat have he head health hear heart heavy help her here high him his history
hold hole home hope horse hospital hot hotel hour house how however hundred
hungry husband idea if important in inside instead interest into is island it
its job join juice jump just keep key kid kill kind kitchen knife know lake
land language large last late later laugh law learn leave left leg less let
letter level lie life light like line list listen little live local long look
lose lot love low lunch machine main make man many map market marry match matter
may maybe me meal mean meat meet member message middle milk million mind minute
miss modern moment money month more morning most mother mountain mouth move
movie much music must my name near nearly need never new news next nice night
nine no nobody north not note nothing now number of off office often oil ok
old on once one only open or orange order other our out outside over own page
paint pair paper parent park part party pass past pay pen people perhaps phone
photo pick picture piece pink place plan plant play please point police poor
popular possible post pound power practice present pretty price problem product
program project public pull push put question quick quietly quite radio rain
read ready real really red remember rest restaurant result return rich ride
right river road rock room round rule run sad safe same save say school science
sea season seat second see seem sell send sentence seven several shall she ship
shirt shoe shop short should show sick side sign simple since sing sister sit
six size sleep slow small smell smile snow so some someone something sometimes
son song soon sorry sound south space speak special spend sport spring stand
star start station stay step still stop store story street strong student study
style such sugar summer sun sure sweet swim system table take talk tall tea
teach team tell ten than thank that the their them then there these they thick
thin thing think thirteen thirty this those though thousand three through throw
thursday ticket time tired to today together tomorrow tonight too top total
touch town train travel tree trip true try turn twelve twenty two type under
understand university until up us use usually vacation vegetable very video
visit voice wait wake walk wall want war warm was wash watch water way we wear
weather week weekend welcome well west what when where which while white who
why wide wife will win wind window winter wish with without woman wonderful
wood word work world worry would write wrong year yellow yes yesterday yet you
young your zero
`.trim().split(/\s+/),
);

const LEVEL_RANK: Record<string, number> = {
  A1: 1,
  A2: 2,
  B1: 3,
  B2: 4,
  C1: 5,
  C2: 6,
};

export function normalizeWord(raw: string): string {
  return raw.toLowerCase().replace(/^[^a-z']+|[^a-z']+$/g, "");
}

/** Focus / hard word: not in easy set, long enough, and above learner level heuristic. */
export function isFocusWord(raw: string, level = "A2"): boolean {
  const word = normalizeWord(raw);
  if (!word || word.length < 4) return false;
  if (EASY_WORDS.has(word)) return false;
  const rank = LEVEL_RANK[level.toUpperCase()] ?? 2;
  // Stricter for lower levels: highlight more; C1+ only longer / rarer
  if (rank <= 2) return word.length >= 4;
  if (rank === 3) return word.length >= 5 || !EASY_WORDS.has(word);
  if (rank === 4) return word.length >= 6;
  return word.length >= 7;
}

export type WordPiece = {
  text: string;
  focus: boolean;
  known: boolean;
};

export function tokenizeCue(
  text: string,
  opts: { level?: string; knownWords?: Set<string> } = {},
): WordPiece[] {
  const level = opts.level ?? "A2";
  const known = opts.knownWords;
  const parts = text.split(/(\s+)/);
  return parts.map((part) => {
    if (/^\s+$/.test(part) || !/[a-zA-Z]/.test(part)) {
      return { text: part, focus: false, known: false };
    }
    const norm = normalizeWord(part);
    const isKnown = !!known?.has(norm);
    return {
      text: part,
      focus: !isKnown && isFocusWord(part, level),
      known: isKnown,
    };
  });
}
