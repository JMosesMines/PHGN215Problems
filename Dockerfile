# ---------- Base ----------
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
	tzdata make build-essential curl git ca-certificates \
	libkpathsea-dev fontforge texlive-binaries \
	texlive-latex-base \
 && rm -rf /var/lib/apt/lists/*

# ---------- Node via nvm (pinned) ----------
SHELL ["/bin/bash", "--login", "-c"]
WORKDIR /code
ENV NODE_VERSION=16.16.0
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash \
 && source ~/.nvm/nvm.sh \
 && nvm install ${NODE_VERSION} \
 && nvm use ${NODE_VERSION} \
 && nvm alias default ${NODE_VERSION}
ENV PATH="/root/.nvm/versions/node/v16.16.0/bin/:${PATH}"

# ---------- Build web2js (TeX -> WASM) ----------
RUN git clone https://github.com/drgrice1/web2js.git
WORKDIR /code/web2js
RUN git checkout d78ef1f3ec94520c88049b1de36ecf6be2a65c10
RUN npm install --fetch-retries=5 \
		--fetch-retry-mintimeout=20000 \
		--fetch-retry-maxtimeout=120000 \
		--no-progress --no-audit --no-fund \
		https://github.com/kisonecat/node-kpathsea.git \
 && npm install --loglevel=warn \
 && npm run build \
 && npm run generate-wasm
RUN npx --yes wasm-opt@1.3.0 \
	out.wasm \
	--asyncify \
	--pass-arg=asyncify-ignore-indirect \
	--pass-arg=asyncify-imports@library.reset \
	-O4 -o tex.wasm

# ---------- Overlay preamble, dump core ----------
# COPY initex.js /code/web2js/initex.js
RUN ln -sf tex.js latex
# Insert \usepackage{circuitikz} right after \usepackage{tikz} in the repo's initex.js
RUN sed -i '0,/\\\\usepackage{tikz}/s//\\\\usepackage{tikz}\n\\\\usepackage{circuitikz}/' initex.js
RUN node initex.js
RUN ls -lh core.dump || (echo "initex.js did not produce core.dump"; ls -lh; echo "--- *.log (tail) ---"; tail -n 50 *.log || true; exit 1)
RUN gzip -f tex.wasm && gzip -f core.dump

# ---------- Bring in TikZJax & place artifacts ----------
WORKDIR /code
RUN git clone https://github.com/benrbray/tikzjax.git
RUN cp /code/web2js/tex.wasm.gz /code/tikzjax \
 && cp /code/web2js/core.dump.gz /code/tikzjax
WORKDIR /code/tikzjax
RUN npm install \
 && npm run gen-tex-files \
 && npm run build
