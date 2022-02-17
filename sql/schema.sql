CREATE TABLE users (id SERIAL PRIMARY KEY, first_name varchar(250), last_name VARCHAR(250),  email VARCHAR(200) NOT NULL UNIQUE, passcode VARCHAR(100), created TIMESTAMP NOT NULL DEFAULT NOW(), passcode_created TIMESTAMP, last_seen TIMESTAMP DEFAULT now());


INSERT INTO users (first_name,last_name,email,passcode,passcode_created,last_seen) VALUES ('Matias','Garafoni','matias.garafoni@gmail.com',12345,NOW(),NOW());