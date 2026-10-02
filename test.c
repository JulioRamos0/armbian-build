	cfg->f_max = 50000000;
#ifdef CONFIG_SPL_BUILD
	cfg->f_max = 25000000;
	cfg->host_caps = 0;
#endif
