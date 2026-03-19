# Magento docker installer
## Description
This is a project to easily launch a Magento project on docker.
/!\ Only dev environment support for the moment /!\

## Table of contents
- [Description](#description)
- [Table of contents](#table-of-contents)
- [Getting started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Technologies used](#technologies-used)
  - [Installation and run](#installation-and-run)
- [Usage](#usage)
- [Authors](#authors)
- [License](#license)
  
## Getting started
### Prerequisites
- `Docker v29.2.1` or higher.
- `Docker compose v5.0.2` or higher.
- Tested on Arch linux.

### Technologies used
![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=fff)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=fff)
![Docker Compose](https://img.shields.io/badge/Docker-Compose-gray?logo=docker&logoColor=fff&labelColor=2496ED)  

### Installation and run
> Copy / paste and execute this command in you terminal
```bash
git clone https://github.com/Franck-dev-hub/magento-docker-installer
mv magento-docker-installer/setup_magento.sh ./
rm -r magento-docker-installer
./setup_magento.sh
```

## Usage
Once the application is running, you just have to read the logs in your terminal.

## Authors
- **[Franck S.](https://github.com/Franck-dev-hub)**

## License
This project is licensed under GNU AGPL v3.0 - see the LICENSE.txt file for details.
