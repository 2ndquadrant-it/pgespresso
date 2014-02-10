MODULES = pgespresso
OBJS = pgespresso.o
EXTENSION = pgespresso
DATA = pgespresso--0.1.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
