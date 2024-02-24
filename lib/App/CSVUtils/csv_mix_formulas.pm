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
    name => 'csv_concat',
    summary => 'Mix several formulas/recipes (lists of ingredients and their weights/volumes) into one, '.
        'and output the combined formula',
    description => <<'_',

Each formula is a CSV comprised of at least two fields. The first field is
assumed to contain the name of ingredients. The second field is assumed to
contain the weight of ingredients. A percent form is recognized and will be
converted to its decimal form (e.g. "60%" or "60.0 %" will become 0.6).

Example, mixing this CSV:

    ingredient,%weight
    water,80
    sugar,15
    citric acid,0.3
    strawberry syrup,4.7

and this (notice the different headers, which will be ignored):

    Ingredient,% of Weight
    lemon syrup,5.75
    citric acid,0.25
    sugar,14
    water,80

will result in (the header by default will follow the first CSV and ingredients
will be sorted by decreasing weight):

    ingredient,%weight
    water,80
    sugar,14.5
    lemon syrup,2.875
    strawberry syrup,2.35
    citric acid,0.275

Keywords: compositions, mixture, combine

_
    add_args => {
    },
    tags => ['category:combining'],

    reads_multiple_csv => 1,

    on_input_data_row => sub {
        my $r = shift;

        # keys we add to the stash
        $r->{ingredients} //= {}; # key = ingredient name, val = [weight1, weight2, ...]
        unless (defined $r->{output_fields}) {
            $r->{output_fields} = $r->{input_fields};
            $r->{output_fields_idx} = $r->{input_fields_idx};
        }

        my $ingredient = $r->{input_fields}[0];
        my $weight = $r->{input_fields}[1];
        if ($weight =~ /\A(.+?)\s*%\z/) { $weight = $1 * 0.01 }
        $r->{ingredients}{ $ingredient } //= [];
        push @{ $r->{ingredients}{ $ingredient } }, $weight;
    },

    after_close_input_files => sub {
        my $r = shift;

        my $num_formulas = @{ $r->{input_filenames} };
        return unless $num_formulas;

        # calculate the weights of the mixed formula
        my $mixed_formula = {}; # key=ingredient name, val=weight
        for my $ingredient (keys %{ $r->{ingredients} }) {
            $mixed_formula->{$ingredient} = sum( @{ $r->{ingredients}{$ingredient} } ) / $num_formulas;
        }

        for my $ingredient (sort { $mixed_formula->{$b} <=> $mixed_formula->{$a} } keys %$mixed_formula) {
            $r->{code_print_row}->([$ingredient, $mixed_formula->{$ingredient}]);
        }
    },
);

1;
# ABSTRACT:

=cut
