MODULES = pgespresso
OBJS = pgespresso.o
EXTENSION = pgespresso
DATA = pgespresso--1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
