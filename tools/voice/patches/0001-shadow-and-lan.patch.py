#!/usr/bin/env python3
"""Apply AcquireEnglish patches onto vendored Zemksh/voice main.py (idempotent)."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / 'vendor' / 'zemksh-voice' / 'backend' / 'app' / 'main.py'

MARKER = '# --- acquireenglish shadow/lan patch ---'

SHADOW_HELPERS = r'''
# --- acquireenglish shadow/lan patch ---
import re as _ae_re
from uuid import uuid4 as _ae_uuid4

def _ae_allow_lan() -> bool:
    return os.getenv('VOICE_ALLOW_LAN', 'false').lower() in {'1', 'true', 'yes', 'on'}

def _ae_tokenize(text: str) -> list[str]:
    return _ae_re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)?", (text or '').lower())

def _ae_overlap(reference: str, hypothesis: str) -> dict:
    ref = _ae_tokenize(reference)
    hyp = _ae_tokenize(hypothesis)
    if not ref and not hyp:
        return {
            'score': 1.0,
            'precision': 1.0,
            'recall': 1.0,
            'missing_words': [],
            'extra_words': [],
            'reference_words': 0,
            'hypothesis_words': 0,
        }
    from collections import Counter
    ref_c, hyp_c = Counter(ref), Counter(hyp)
    overlap = sum((ref_c & hyp_c).values())
    precision = overlap / len(hyp) if hyp else 0.0
    recall = overlap / len(ref) if ref else 0.0
    f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    return {
        'score': round(f1, 4),
        'precision': round(precision, 4),
        'recall': round(recall, 4),
        'missing_words': sorted((ref_c - hyp_c).elements()),
        'extra_words': sorted((hyp_c - ref_c).elements()),
        'reference_words': len(ref),
        'hypothesis_words': len(hyp),
    }
'''

LAN_MIDDLEWARE_REPLACEMENT = r'''
    @app.middleware('http')
    async def local_only(request: Request, call_next):
        from urllib.parse import urlparse
        allowed = {'127.0.0.1', 'localhost', '::1', 'testserver'}
        allow_lan = _ae_allow_lan()
        if not allow_lan and request.url.hostname not in allowed:
            return JSONResponse({'detail': 'Only local access is allowed.'}, status_code=403)
        origin = request.headers.get('origin')
        if origin and not allow_lan:
            if origin not in {f'http://{host}:{port}' for host in ('127.0.0.1', 'localhost') for port in (5173, 8000, 8765)}:
                return JSONResponse({'detail': 'Requests must come from the local application.'}, status_code=403)
        if request.headers.get('sec-fetch-site') == 'cross-site' and not allow_lan:
            return JSONResponse({'detail': 'Cross-site requests are not allowed.'}, status_code=403)
        response = await call_next(request)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['Cache-Control'] = 'no-store'
        response.headers['Content-Security-Policy'] = "default-src 'self'; connect-src 'self'; media-src 'self' blob:; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
        return response
'''

SHADOW_ROUTE = r'''
    @app.post('/api/shadow')
    def shadow_sentence(
        reference_text: str = Form(min_length=1, max_length=2000),
        file: UploadFile = File(),
    ):
        """Sentence shadowing: Whisper transcript + word-overlap vs reference.

        Does not require Gemma / 20-word essay analysis. Ideal for 影子跟读.
        """
        reference = reference_text.strip()
        if not reference:
            raise HTTPException(422, 'Enter the reference English sentence.')
        suffix = Path(file.filename or '').suffix.lower() or '.wav'
        if suffix not in MEDIA and suffix != '.wav':
            raise HTTPException(415, 'Choose an m4a, mp3, wav, or webm recording.')
        sid = _ae_uuid4().hex
        directory = settings.data_dir / 'audio' / f'shadow-{sid}'
        directory.mkdir(parents=True, mode=0o700)
        try:
            size = 0
            with (directory / 'original').open('wb') as target:
                while chunk := file.file.read(1024 * 1024):
                    size += len(chunk)
                    if size > settings.max_upload_mb * 1024 * 1024:
                        raise HTTPException(413, f'Upload exceeds {settings.max_upload_mb} MB.')
                    target.write(chunk)
            if size == 0:
                raise HTTPException(422, 'The file is empty.')
            duration = convert_audio(directory / 'original', directory / 'normalized.wav', settings)
            transcript = transcribe(directory / 'normalized.wav', settings)
            overlap = _ae_overlap(reference, transcript)
            return {
                'id': sid,
                'kind': 'shadow',
                'reference_text': reference,
                'transcript': transcript,
                'duration': duration,
                'mock': settings.mock,
                'overlap': overlap,
                'label': 'Local shadowing feedback · Whisper transcript + word overlap (not a certified pronunciation score).',
            }
        except PracticeError as exc:
            raise HTTPException(422, str(exc)) from None
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(500, 'Local shadow processing failed. Check FFmpeg / Whisper setup.') from None
        finally:
            file.file.close()
            shutil.rmtree(directory, ignore_errors=True)
'''


def apply() -> None:
    text = MAIN.read_text(encoding='utf-8')
    if MARKER in text:
        print('shadow/lan patch already present')
        return

    # Insert helpers after imports / constants block (before class Worker)
    anchor = 'class Worker:'
    if anchor not in text:
        raise SystemExit('could not find Worker class in main.py')
    text = text.replace(anchor, SHADOW_HELPERS + '\n' + anchor, 1)

    # Replace local_only middleware body
    start = text.find("    @app.middleware('http')\n    async def local_only")
    if start < 0:
        raise SystemExit('could not find local_only middleware')
    end = text.find('\n    def get_session', start)
    if end < 0:
        raise SystemExit('could not find get_session after middleware')
    text = text[:start] + LAN_MIDDLEWARE_REPLACEMENT.rstrip() + '\n' + text[end:]

    # Insert /api/shadow before frontend static mount
    mount = "    dist = SOURCE / 'frontend' / 'dist'"
    if mount not in text:
        raise SystemExit('could not find frontend mount')
    text = text.replace(mount, SHADOW_ROUTE.rstrip() + '\n\n' + mount, 1)

    MAIN.write_text(text, encoding='utf-8')
    print(f'patched {MAIN}')


if __name__ == '__main__':
    apply()
