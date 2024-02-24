package App::CSVUtils::csv_mix_formulas;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                );
use List::Util qw(sum);

gen_csv_util(
    name => 'csv_mix_formulas',
    summary => 'Mix several formulas/recipes (lists of ingredients and their weights/volumes) into one, '.
        'and output the combined formula',
    description => <<'_',

Each formula is a CSV comprised of at least two fields. The first field is
assumed to contain the name of ingredients. The second field is assumed to
contain the weight of ingredients. A percent form is recognized and will be
converted to its decimal form (e.g. "60%" or "60.0 %" will become 0.6).

Example, mixing this CSV:

    ingredient,%weight,extra-field1,extra-field2
    water,80,foo,bar
    sugar,15,foo,bar
    citric acid,0.3,foo,bar
    strawberry syrup,4.7,foo,bar

and this:

    ingredient,%weight,extra-field1,extra-field2,extra-field3
    lemon syrup,5.75,bar,baz,qux
    citric acid,0.25,bar,baz,qux
    sugar,14,bar,baz,qux
    water,80,bar,baz,qux

will result in the following CSV. Note: 1) for the header, except for the first
two fields which are the ingredient name and weight which will contain the mixed
formula, the other fields will simply collect values from all the CSV files. 2)
for sorting order: decreasing weight then by name.

    ingredient,%weight,extra-field1,extra-field2,extra-field3
    water,80,foo,bar,qux
    sugar,14.5,foor,bar,qux
    lemon syrup,2.875,bar,baz,qux
    strawberry syrup,2.35,foo,bar,
    citric acid,0.275,foo,bar,qux

Keywords: compositions, mixture, combine

_
    add_args => {
        output_format => {
            summary => 'A sprintf() template to format the weight',
            schema => 'str*',
            tags => ['formatting'],
        },
        output_percent => {
            summary => 'If enabled, will convert output weights to percent with the percent sign (e.g. 0.6 to "60%")',
            schema => 'bool*',
            tags => ['formatting'],
        },
        output_percent_nosign => {
            summary => 'If enabled, will convert output weights to percent without the percent sign (e.g. 0.6 to "60")',
            schema => 'bool*',
            tags => ['formatting'],
        },
    },
    add_args_rels => {
        choose_one => ['output_percent', 'output_percent_nosign'],
    },
    tags => ['category:combining'],

    # we modify from csv-concat

    reads_multiple_csv => 1,

    before_open_input_files => sub {
        my $r = shift;

        # we add the following keys to the stash
        $r->{all_input_fields} = [];
        $r->{all_input_fh} = [];
        $r->{ingredient_field} = undef;
        $r->{weight_field} = undef;
    },

    on_input_header_row => sub {
        my $r = shift;

        # TODO: allow to customize
        if ($r->{input_filenum} == 1) {
            die "csv-mix-formulas: At least 2 fields are required\n" unless @{ $r->{input_fields} } >= 2;

            $r->{ingredient_field} = $r->{input_fields}[0];
            $r->{weight_field}     = $r->{input_fields}[1];
        }

        # after we read the header row of each input file, we record the fields
        # as well as the filehandle, so we can resume reading the data rows
        # later. before printing all the rows, we collect all the fields from
        # all files first.

        push @{ $r->{all_input_fields} }, $r->{input_fields};
        push @{ $r->{all_input_fh} }, $r->{input_fh};
        $r->{wants_skip_file}++;
    },

    after_close_input_files => sub {
        my $r = shift;

        # collect all output fields
        $r->{output_fields} = [];
        $r->{output_fields_idx} = {};
        for my $i (0 .. $#{ $r->{all_input_fields} }) {
            my $input_fields = $r->{all_input_fields}[$i];
            for my $j (0 .. $#{ $input_fields }) {
                my $field = $input_fields->[$j];
                unless (grep {$field eq $_} @{ $r->{output_fields} }) {
                    push @{ $r->{output_fields} }, $field;
                    $r->{output_fields_idx}{$field} = $#{ $r->{output_fields} };
                }
            }
        }

        my $ingredients = {}; # key = ingredient name, { field=> ... }

        # get all ingredients
        my $csv = $r->{input_parser};
        for my $i (0 .. $#{ $r->{all_input_fh} }) {
            my $fh = $r->{all_input_fh}[$i];
            my $input_fields = $r->{all_input_fields}[$i];
            while (my $row = $csv->getline($fh)) {
                my $ingredient = $row->[ $r->{input_fields_idx}{ $r->{ingredient_field} } ];
                my $weight     = $row->[ $r->{input_fields_idx}{ $r->{weight_field} } ];
                $ingredients->{$ingredient} //= {};
                my $ingredient_row = $ingredients->{$ingredient};
                for my $j (0 .. $#{ $input_fields }) {
                    my $field = $input_fields->[$j];
                    if ($field eq $r->{weight_field}) {
                        $ingredient_row->{$field} //= [];
                        push @{ $ingredient_row->{$field} }, $row->[$j];
                    } else {
                        $ingredient_row->{$field} //= $row->[$j];
                    }
                }
            }
        }

        #use DD; dd $ingredients;

        my $num_formulas = @{ $r->{input_filenames} };
        return unless $num_formulas;

        # calculate the weights of the mixed formula
        for my $ingredient (keys %{ $ingredients }) {
            $ingredients->{$ingredient}{ $r->{weight_field} } = sum( @{ $ingredients->{$ingredient}{ $r->{weight_field} } } ) / $num_formulas;
        }

        for my $ingredient (sort { ($ingredients->{$b}{ $r->{weight_field} } <=> $ingredients->{$a}{ $r->{weight_field} }) ||
                                       (lc($a) cmp lc($b)) } keys %$ingredients) {

          FORMAT: for my $weight ($ingredients->{ $r->{weight_field} }) {
                if ($r->{util_args}{output_percent}) {
                    $weight = ($weight * 100) . "%";
                    last FORMAT;
                } elsif ($r->{util_args}{output_percent_nosign}) {
                    $weight = ($weight * 100);
                }
                if ($r->{util_args}{output_format}) {
                    $weight = sprintf($r->{util_args}{output_format}, $weight);
                }
            } # FORMAT

            $r->{code_print_row}->($ingredients->{$ingredient});
        }
    },
);

1;
# ABSTRACT:

=cut
