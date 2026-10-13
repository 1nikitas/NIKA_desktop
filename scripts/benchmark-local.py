#!/usr/bin/env python3
"""Воспроизводимый замер скорости llama.cpp; без сети, аккаунта и истории чатов."""
import argparse
import datetime
import hashlib
import json
import pathlib
import platform
import shutil
import subprocess
import sys


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=pathlib.Path, help="Существующий файл GGUF")
    parser.add_argument("--output", type=pathlib.Path, required=True, help="Новый каталог результатов")
    parser.add_argument("--sha256", help="Ожидаемый SHA-256 модели; остановка при несовпадении")
    parser.add_argument("--repetitions", type=int, default=5)
    args = parser.parse_args()
    if not args.model.is_file() or args.repetitions < 2:
        parser.error("Укажи существующий GGUF и минимум два повтора")
    engine = shutil.which("llama-bench")
    if not engine:
        parser.error("llama-bench не найден: сначала установи llama.cpp")
    if args.output.exists():
        parser.error("Каталог результатов уже существует; выбери новый")
    digest = hashlib.sha256()
    with args.model.open("rb") as source:
        if source.read(4) != b"GGUF":
            parser.error("Это не файл GGUF")
        source.seek(0)
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    sha = digest.hexdigest()
    if args.sha256 and sha != args.sha256.lower():
        parser.error("SHA-256 не совпадает; замер не запущен")
    args.output.mkdir(parents=True)
    invocation = [engine, "-m", str(args.model.resolve()), "-p", "512", "-n", "128",
                  "-r", str(args.repetitions), "-ngl", "99", "-t", "8", "-b", "2048",
                  "-ub", "512", "-ctk", "f16", "-ctv", "f16", "-fa", "on", "-o", "json"]
    metadata = {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "os": platform.system(), "os_version": platform.mac_ver()[0],
        "cpu": command("sysctl", "-n", "machdep.cpu.brand_string"),
        "physical_memory_bytes": int(command("sysctl", "-n", "hw.memsize")),
        "model_filename": args.model.name, "model_bytes": args.model.stat().st_size,
        "model_sha256": sha, "repetitions": args.repetitions, "warmup": "llama-bench default",
        "command": ["llama-bench", "-m", "<GGUF>"] + invocation[3:],
        "scope": "llama.cpp synthetic throughput; not app latency, answer quality or an 8 GB validation",
    }
    (args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    with (args.output / "raw.json").open("w") as out, (args.output / "engine.log").open("w") as err:
        result = subprocess.run(invocation, stdout=out, stderr=err)
    if result.returncode:
        sys.exit(f"Ошибка llama-bench ({result.returncode}); подробности: {args.output / 'engine.log'}")
    rows = json.loads((args.output / "raw.json").read_text())
    if not isinstance(rows, list) or len(rows) != 2 or any(row.get("avg_ts", 0) <= 0 for row in rows):
        sys.exit("Неожиданный формат результата; исходные данные сохранены, отчёт не создан")
    lines = ["# Скорость локального движка", "", f"{metadata['cpu']} · {metadata['physical_memory_bytes'] / 2**30:g} ГиБ · macOS {metadata['os_version']}",
             "", f"Модель: `{args.model.name}`. {args.repetitions} повторов, прогрев включён.", "",
             "| Тест | Среднее, токенов/с | Стандартное отклонение |", "| --- | ---: | ---: |"]
    for row in rows:
        label = f"pp{row['n_prompt']}" if row['n_prompt'] else f"tg{row['n_gen']}"
        lines.append(f"| {label} | {row['avg_ts']:.2f} | {row['stddev_ts']:.2f} |")
    lines += ["", "Синтетическая нагрузка llama.cpp; не сквозная задержка NIKA и не оценка качества ответов.",
              "Результат на этом оборудовании не предсказывает скорость на Mac с 8 ГБ.",
              "Версия движка, параметры и все повторы — в raw.json; хеш модели и оборудование — в environment.json.", ""]
    (args.output / "RESULTS.md").write_text("\n".join(lines))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
