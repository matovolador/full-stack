# Full-Stack APP

## Techstack
All sides of the application are deployed with Docker and docker-compose. This includes frontend (VueJS), backend (Flask) , proxy server (nginx), and PostreSQL (DB).
### Backend: 
[![Coverage Status](./backend/coverage-badge.svg?dummy=8484744)](./backend/coverage.xml)
* Python Flask
* PostgreSQL
* Unittests
* Code Coverage


### Frontend:
* VueJS

### Database:
* PostgreSQL

# Backend Info:
Assumes your virtual environment is called "venv" and its 1 level inside "backend" folder.
## Tests:
Run tests by using `backend/tests.sh`. This script will create migrations, run all tests, and rollback all migrations. Will also generate code coverage files and badge.


# TODO
* Write more info about backend
* Write ANYTHING about frontend