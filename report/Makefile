report.pdf: report.tex tables/macros.tex
	latexmk -pdf -interaction=nonstopmode report.tex

tables/macros.tex: make_tables.py ../results/runs.json
	python3 make_tables.py

clean:
	latexmk -C; rm -rf tables
