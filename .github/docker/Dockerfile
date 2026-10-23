# The CI image of Bartleby: the TeX packages, fonts, and pandocs of the
# compile smoke tests and of the cheat sheet build, installed once here,
# because apt took 13 to 15 minutes for them in each job. Vim is not
# here: install-vim fetches the latest one in each job, because the tests
# need a recent patch level. ci-image.yml builds and pushes it.

# The Ubuntu of ubuntu-latest, so that the distro pandoc is the one that
# users of that Ubuntu have.
FROM ubuntu:24.04

# The pandoc release that the smoke tests run besides the distro one, as
# Homebrew has. ENV keeps it in the image, so that ci.yml finds its
# folder, /opt/pandoc-<release>/bin.
ARG PANDOC_RELEASE=3.10
ENV PANDOC_RELEASE=${PANDOC_RELEASE}

# Links the package on ghcr.io to the repository, so that the workflows
# of the repository can pull it with their own token.
LABEL org.opencontainers.image.source=https://github.com/Galvarcus/bartleby

# The smoke tests need the first five TeX packages, texlive-xetex and the
# DejaVu Serif of fonts-dejavu-core for the Book PDF. The cheat sheet
# needs texlive-latex-recommended, fonts-texgyre, and fonts-dejavu-mono.
# git, curl, jq, and ca-certificates are for the steps: checkout,
# install-vim, and the commit of the cheat sheet.
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    texlive-latex-extra texlive-fonts-recommended texlive-plain-generic \
    texlive-latex-recommended texlive-xetex \
    fonts-dejavu-core fonts-dejavu-mono fonts-texgyre \
    pandoc python3 git curl jq ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/jgm/pandoc/releases/download/${PANDOC_RELEASE}/pandoc-${PANDOC_RELEASE}-linux-amd64.tar.gz" \
    | tar -xz -C /opt \
  && /opt/pandoc-${PANDOC_RELEASE}/bin/pandoc --version | head -1 \
  && pandoc --version | head -1 \
  && xelatex --version | head -1
