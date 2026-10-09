from setuptools import setup, find_packages

setup(
    name="music-cli",
    version="1.0.0",
    description="音乐平台后端（NestJS）的 CLI-Anything 风格 harness",
    packages=find_packages(),
    install_requires=["click>=8.0", "requests>=2.28"],
    python_requires=">=3.10",
    entry_points={"console_scripts": ["music-cli=music_cli.music_cli:main"]},
)
