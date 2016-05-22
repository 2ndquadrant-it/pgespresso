MODULES = pgespresso
OBJS = pgespresso.o
EXTENSION = pgespresso
DATA = $(wildcard pgespresso--*.sql)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
