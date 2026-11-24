"""Self-improvement (expert iteration): the model learns from its own best work.

1. Run the full generate -> look -> criticise -> fix loop on many prompts.
2. Keep only results the loop judged good (score >= --min-score).
3. Write them as new training rows:
     planner:  request -> the FINAL (best) spec      (so next time it gets there in one shot)
     critic:   render of an earlier attempt -> the critique whose patch actually raised the score
4. Also write DPO pairs (best spec vs. worst spec for the same prompt) for preference training.
5. Re-train with sft_lora.py on synthetic + self-improvement rows. Repeat.

usage:
  python training/self_improve.py --model /content/drive/MyDrive/Mujassam/mujassam-4.9b \
      --prompts training/prompts_ar_en.txt --out data/round1
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from mujassam.brain import prompts as P  # noqa: E402
from mujassam.dsl.schema import compact_spec  # noqa: E402
from mujassam.model import MujassamModel  # noqa: E402


def _row(task, msgs, answer):
    def ser(m):
        c = m["content"]
        if isinstance(c, str):
            return {"role": m["role"], "content": c}
        return {"role": m["role"], "content": [x if x["type"] == "text" else {"type": "image", "image": str(x["image"])} for x in c]}
    return {"task": task, "messages": [ser(m) for m in msgs] +
            [{"role": "assistant", "content": json.dumps(answer, separators=(",", ":"), ensure_ascii=False)}]}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="mujassam-4.9b")
    ap.add_argument("--prompts", required=True, help="text file, one request per line")
    ap.add_argument("--out", default="data/self_improve")
    ap.add_argument("--preset", default="quality")
    ap.add_argument("--min-score", type=float, default=8.0)
    ap.add_argument("--lora", default=None)
    a = ap.parse_args()

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    model = MujassamModel.from_pretrained(a.model, load_recon=False, brain_lora=a.lora)
    prompts = [l.strip() for l in Path(a.prompts).read_text(encoding="utf-8").splitlines() if l.strip()]
    kept = 0
    with open(out / "train.jsonl", "a", encoding="utf-8") as sft, open(out / "dpo.jsonl", "a", encoding="utf-8") as dpo:
        for i, prompt in enumerate(prompts):
            try:
                res = model.generate_from_text(prompt, out / f"job_{i:05d}", a.preset)
            except Exception as e:  # noqa: BLE001
                print(f"[{i}] failed: {e}")
                continue
            best = res.best
            print(f"[{i}] score {res.score:.2f} after {len(res.attempts)} attempts: {prompt[:60]}")
            if best is None or best.score < a.min_score:
                continue
            kept += 1
            sft.write(json.dumps(_row("planner", P.planner_messages(prompt, res.route), compact_spec(best.spec)),
                                 ensure_ascii=False) + "\n")
            # critiques that led to an improvement are good critic targets
            atts = res.attempts
            for prev, nxt in zip(atts, atts[1:]):
                if nxt.source == "patch" and nxt.score > prev.score + 0.3 and prev.build.grid:
                    msgs = P.critic_messages(prompt, prev.build.grid,
                                             json.dumps(compact_spec(prev.spec), separators=(",", ":")),
                                             prev.tech.text(prev.build.stats), res.route.get("checklist"))
                    c = prev.critique
                    sft.write(json.dumps(_row("critic", msgs, {"scores": c.scores, "overall": c.overall,
                                                               "issues": c.issues, "patch": c.patch, "done": False}),
                                         ensure_ascii=False) + "\n")
            worst = min(atts, key=lambda x: x.score)
            if worst is not best and best.score - worst.score >= 1.0:
                msgs = P.planner_messages(prompt, res.route)
                dpo.write(json.dumps({"prompt": [m for m in msgs],
                                      "chosen": json.dumps(compact_spec(best.spec), separators=(",", ":")),
                                      "rejected": json.dumps(compact_spec(worst.spec), separators=(",", ":")),
                                      "margin": round(best.score - worst.score, 2)}, ensure_ascii=False, default=str) + "\n")
    print(f"kept {kept}/{len(prompts)} -> {out / 'train.jsonl'} (retrain with sft_lora.py)")


if __name__ == "__main__":
    main()
