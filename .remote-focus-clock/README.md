# Productive Hours Timer

Minimal FastAPI app with a Jinja template for tracking only productive time.

## Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
```

Open `http://127.0.0.1:8000`.

## Use

- The timer starts immediately.
- Press `Space` to pause or resume.
- Paused time is not added to the total.
- Each pause or resume rotates the color theme.
