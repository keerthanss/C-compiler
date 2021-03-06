%{
	#include "hashtable.h"
	#include "symbol_table.cpp"
	#include "icghelper.cpp"
	#include<cstdio>
	#include <stack>
	using namespace std;

	sym_table st;				// The symbol table
	type_e dtype;				// Specifies the datatype of an identifier

	int temp_var_no = 1;		// A global variable that is used to create temporary variables in ICG
	int param_no;						// Used to count number of parameters passed to a function
	int temp_label_no = 1;	// A global variable to hold label numbers
	stack<int> label_s;			// A stack which is used to correctly print labels

	Expr* postfix_id;				// An object reference that holds the variable to be incremented/decremented (unary) after its present value is used in the expression in which it is used
	int postfix_operator;		// Holds the type of unary operator (-- or ++)
	bool postfix=false;			// A boolean that tells whether a post increment or post decrement operator is present in an expression or not

	int yylex(void);
	void yyerror(char *);

	int type_error(type_e t1, type_e t2){ //returns 1 if error, 0 if not
		if(t1 != t2){
			yyerror("Type mismatch!\n");
			return 1;
		}
		return 0;
	}

%}

%union{
	Expr* E;
}

%nonassoc NO_ELSE
%nonassoc  ELSE

%token IDENTIFIER CONSTANT STRING_LITERAL CHAR_CONST
%token INC_OP DEC_OP LEFT_OP RIGHT_OP LE_OP GE_OP EQ_OP NE_OP
%token AND_OP OR_OP MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN ADD_ASSIGN
%token SUB_ASSIGN LEFT_ASSIGN RIGHT_ASSIGN AND_ASSIGN
%token XOR_ASSIGN OR_ASSIGN

%token CHAR INT VOID

%token IF ELSE WHILE DO CONTINUE BREAK RETURN

%start translation_unit
%%

primary_expression: IDENTIFIER	{ value_s* v = st.find_id( $<E->var>1 );
																	if(v == NULL)
																	{
																		yyerror("Undeclared identifier!");
																	}
																	else{
																		$<E>$ = $<E>1;
																		$<E->type>$ = v->type;
																		/*printf("[Type(%s)=%s]", $<E->var>$, ($<E->type>$==Int?"int":"char"));*/
																	}
																}
									| CONSTANT		{$<E>$ = $<E>1;}
									| CHAR_CONST 	{$<E>$ = $<E>1;}
									| STRING_LITERAL	{ $<E->type>$ = Char;}
									| '(' expression ')' {$<E>$ = $<E>2;}
									;

postfix_expression: primary_expression	{ $<E>$ = $<E>1; }
/* Calculate the byte offset for the array element based on the array datatype size. Concatenate the array name with the temporary variable created while
 * calculating the offset, enclosing the offset in []. Print the generated three address code
*/
									| postfix_expression '[' expression ']' {	Expr* tempvar = newTemp(temp_var_no++);		// A function present in 'icghelper.cpp'
																														tempvar->type = $<E->type>3;
																														Expr* temp = $<E>1;
																														Expr* constant;
																														if(temp->type == Int)
																															constant = newTemp("4");
																														else if(temp->type == Char)
																															constant = newTemp("1");
																														tempvar->gen("*", $<E>3, constant);			// A function present in 'icghelper.cpp'
																														temp->set_array($<E>1,tempvar);					// A function present in 'icghelper.cpp'
																														$<E>$ = temp;
																													}
/*
 *	Function call without any arguments.
*/
									| postfix_expression '(' ')' {	Expr* temp=newTemp(temp_var_no++);
																									temp->type = $<E->type>1;
																									temp->call($<E>1, 0);															// A function present in 'icghelper.cpp'
																									$<E>$ = temp;
																								}
/*
 *	Function call with one or more arguments. The number of arguments passed is counted in the rule for 'argument_expression_list'
*/
									| postfix_expression '(' {param_no = 0;} argument_expression_list ')' {	Expr* temp=newTemp(temp_var_no++);
																																					temp->type = $<E->type>1;
																																					temp->call($<E>1, param_no);
																																					param_no = 0;
																																					$<E>$ = temp;
																																				}
									/*
										For postfix increment and decrement, the variable is stored in a temp object called "postfix_id".
										The operator used is also stored in "postfix_operator".
										Once this is done, the flag "postfix" is set to true.
										This flag is then checked in the production of expression, which is the root of the entire subtree of expressions.
									*/
									| postfix_expression INC_OP {	$<E>$ = $<E>1;
																								postfix_id = $<E>$;
																								postfix_operator = INC_OP;
																								postfix = true;
																							}
									| postfix_expression DEC_OP {	$<E>$ = $<E>1;
																								postfix_id = $<E>$;
																								postfix_operator = DEC_OP;
																								postfix = true;
																							}
									;

// Includes action for counting the number of arguments passed to a function
argument_expression_list: assignment_expression {	$<E>$ = $<E>1;
																									Expr* temp = $<E>$;
																									temp->param();
																									param_no++;
																								}
												| argument_expression_list ',' assignment_expression {	$<E>$ = $<E>3;
																																								Expr* temp = $<E>$;
																																								temp->param();
																																								param_no++;
																																							}
												;

/*
 *	Pre-increment operator: Creates a temporary variable for storing the incremented or decremented value and then assigns the variable to be modified to
 * the temporary variable
*/
unary_expression: postfix_expression  { $<E>$ = $<E>1; }
								| INC_OP unary_expression {		Expr* constant = newTemp("1");
																							Expr* tempvar = newTemp(temp_var_no++);
																							tempvar->type = $<E->type>2;
																							tempvar->gen("+", $<E>2, constant);
																							$<E>$ = $<E>2;
																							Expr* assgn = $<E>$;
																							assgn->gen(tempvar);
																					}
								| DEC_OP unary_expression {		Expr* constant = newTemp("1");
																							Expr* tempvar = newTemp(temp_var_no++);
																							tempvar->type = $<E->type>2;
																							tempvar->gen("-", $<E>2, constant);
																							$<E>$ = $<E>2;
																							Expr* assgn = $<E>$;
																							assgn->gen(tempvar);
																					}
								| unary_operator cast_expression
								;

unary_operator: '&'
							| '*'
							| '+'
							| '-'
							| '~'
							| '!'
							;

cast_expression	: unary_expression { $<E>$ = $<E>1; }
								| '(' datatype ')' cast_expression { $<E>$ = $<E>4;
																										$<E->type>$ = dtype; //changing type to new datatype, which is then propagated upwards
																									}
								;

multiplicative_expression	: cast_expression { $<E>$ = $<E>1; }
													| multiplicative_expression '*' cast_expression	{	if( !type_error($<E->type>1, $<E->type>3) ){
																																										Expr* temp = newTemp(temp_var_no++);
																																										temp->type = $<E->type>1;
																																										temp->gen("*", $<E>1, $<E>3); //generate 3-addr multiplication code
																																										$<E>$ = temp;
																																									}
																																					}
													| multiplicative_expression '/' cast_expression {if( !type_error($<E->type>1, $<E->type>3) ){
																																										Expr* temp = newTemp(temp_var_no++);
																																										temp->type = $<E->type>1;
																																										temp->gen("/", $<E>1, $<E>3); //generate 3-addr division code
																																										$<E>$ = temp;
																																									}
																																					}
													| multiplicative_expression '%' cast_expression { if( !type_error($<E->type>1, $<E->type>3) ){
																																										Expr* temp = newTemp(temp_var_no++);
																																										temp->type = $<E->type>1;
																																										temp->gen("%", $<E>1, $<E>3); //generate 3-addr mod code
																																										$<E>$ = temp;
																																									}
																																					}
													;

additive_expression	: multiplicative_expression { $<E>$ = $<E>1; }
										| additive_expression '+' multiplicative_expression	{	if( !type_error($<E->type>1, $<E->type>3) ){
																																							Expr* temp = newTemp(temp_var_no++);
																																							temp->type = $<E->type>1;
																																							temp->gen("+", $<E>1, $<E>3); //generate 3-addr addition code
																																							$<E>$ = temp;
																																						}
																																				}
										| additive_expression '-' multiplicative_expression	{if( !type_error($<E->type>1, $<E->type>3) ){
																																							Expr* temp = newTemp(temp_var_no++);
																																							temp->type = $<E->type>1;
																																							temp->gen("-", $<E>1, $<E>3); //generate 3-addr subtraction code
																																							$<E>$ = temp;
																																						}
																																					}
										;

shift_expression: additive_expression { $<E>$ = $<E>1; }
								| shift_expression LEFT_OP additive_expression	{if( !type_error($<E->type>1, $<E->type>3) )
																																		$<E->type>$ = $<E->type>1;}
								| shift_expression RIGHT_OP additive_expression {if( !type_error($<E->type>1, $<E->type>3) )
																																		$<E->type>$ = $<E->type>1;}
								;

relational_expression	: shift_expression { $<E->type>$ = $<E->type>1; }
											| relational_expression '<' shift_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																								Expr* temp = newTemp(temp_var_no++);
																																								temp->type = $<E->type>1;
																																								temp->gen("<", $<E>1, $<E>3); //generate 3-addr relop-L code
																																								$<E>$ = temp;
																																			}
																																		}
											| relational_expression '>' shift_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																								Expr* temp = newTemp(temp_var_no++);
																																								temp->type = $<E->type>1;
																																								temp->gen(">", $<E>1, $<E>3); //generate 3-addr relop-G code
																																								$<E>$ = temp;
																																			}
																																		}
											| relational_expression LE_OP shift_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																								Expr* temp = newTemp(temp_var_no++);
																																								temp->type = $<E->type>1;
																																								temp->gen("<=", $<E>1, $<E>3); //generate 3-addr relop-LE code
																																								$<E>$ = temp;
																																				}
																																			}
											| relational_expression GE_OP shift_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																								Expr* temp = newTemp(temp_var_no++);
																																								temp->type = $<E->type>1;
																																								temp->gen(">=", $<E>1, $<E>3); //generate 3-addr relop-GE code
																																								$<E>$ = temp;
																																				}
																																			}
											;

equality_expression	: relational_expression { $<E->type>$ = $<E->type>1; }
										| equality_expression EQ_OP relational_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																							Expr* temp = newTemp(temp_var_no++);
																																							temp->type = $<E->type>1;
																																							temp->gen("==", $<E>1, $<E>3); //generate 3-addr relop-EQ code
																																							$<E>$ = temp;
																																				}
																																			}
										| equality_expression NE_OP relational_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																							Expr* temp = newTemp(temp_var_no++);
																																							temp->type = $<E->type>1;
																																							temp->gen("!=", $<E>1, $<E>3); //generate 3-addr relop-NE code
																																							$<E>$ = temp;
																																				}
																																			}
										;

and_expression: equality_expression { $<E->type>$ = $<E->type>1; }
							| and_expression '&' equality_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																				Expr* temp = newTemp(temp_var_no++);
																																				temp->type = $<E->type>1;
																																				temp->gen("&", $<E>1, $<E>3); //generate 3-addr bitwise-AND code
																																				$<E>$ = temp;
																													}
																												}
							;

exclusive_or_expression	: and_expression { $<E->type>$ = $<E->type>1; }
												| exclusive_or_expression '^' and_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																									Expr* temp = newTemp(temp_var_no++);
																																									temp->type = $<E->type>1;
																																									temp->gen("^", $<E>1, $<E>3);  //generate 3-addr exclusive-OR code
																																									$<E>$ = temp;
																																				}
																																			}
												;

inclusive_or_expression	: exclusive_or_expression { $<E->type>$ = $<E->type>1; }
												| inclusive_or_expression '|' exclusive_or_expression {	if( !type_error($<E->type>1, $<E->type>3) ){
																																									Expr* temp = newTemp(temp_var_no++);
																																									temp->type = $<E->type>1;
																																									temp->gen("|", $<E>1, $<E>3);  //generate 3-addr inclusive-OR code
																																									$<E>$ = temp;
																																								}
																																							}
												;

logical_and_expression: inclusive_or_expression { $<E->type>$ = $<E->type>1; }
											| logical_and_expression AND_OP inclusive_or_expression {if( !type_error($<E->type>1, $<E->type>3) ){
																																									Expr* temp = newTemp(temp_var_no++);
																																									temp->type = $<E->type>1;
																																									temp->gen("&&", $<E>1, $<E>3); //generate 3-addr AND code
																																									$<E>$ = temp;
																																								}
																																							}
											;

logical_or_expression	: logical_and_expression { $<E->type>$ = $<E->type>1; }
											| logical_or_expression OR_OP logical_and_expression {if( !type_error($<E->type>1, $<E->type>3) ){
																																								Expr* temp = newTemp(temp_var_no++);
																																								temp->type = $<E->type>1;
																																								temp->gen("||", $<E>1, $<E>3); //generate 3-addr OR code
																																								$<E>$ = temp;
																																							}
																																						}
											;

conditional_expression: logical_or_expression { $<E>$ = $<E>1; }
											| logical_or_expression '?' expression ':' conditional_expression
											;

assignment_expression	: conditional_expression { $<E>$ = $<E>1; }
											| unary_expression assignment_operator assignment_expression { if(!type_error($<E->type>1, $<E->type>3)){
																																												$<E>$ = $<E>1;
																																												Expr* temp = $<E>$;
																																												temp->gen($<E>3); //generate assignment instruction
																																											};
																																										}
											;

assignment_operator	: '='
										| MUL_ASSIGN
										| DIV_ASSIGN
										| MOD_ASSIGN
										| ADD_ASSIGN
										| SUB_ASSIGN
										| LEFT_ASSIGN
										| RIGHT_ASSIGN
										| AND_ASSIGN
										| XOR_ASSIGN
										| OR_ASSIGN
										;

expression: assignment_expression { $<E>$ = $<E>1;
																		if(postfix){
																			//if postfix flag is set, the instructions for postfix increment and decrement need to be generated here.
																			Expr* constant = newTemp("1");
																			Expr* tempvar = newTemp(temp_var_no++);
																			tempvar->type = postfix_id->type;
																			if(postfix_operator == INC_OP)
																				tempvar->gen("+", postfix_id, constant);
																			else if(postfix_operator == DEC_OP)
																				tempvar->gen("-", postfix_id, constant);
																			postfix_id->gen(tempvar);
																			postfix = false;
																			}
																	}
						| expression ',' assignment_expression
						;

declaration	: datatype init_declarator_list ';'
						;

init_declarator_list: init_declarator
										| init_declarator_list ',' init_declarator
										;

init_declarator	: declarator
								| declarator '=' initializer {value_s* v = st.find_id( $<E->var>1 );
																								if( !type_error(v->type, $<E->type>3) ){
																										$<E>$ = $<E>1;
																										$<E->type>$ = v->type;
																										Expr* temp = $<E>$;
																										temp->gen($<E>3);
																								}
																							}
								;

datatype: VOID 	{dtype = Void;}
				| CHAR	{dtype = Char;}
				| INT		{dtype = Int;}
				;

declarator: IDENTIFIER		{	$<E>$ = $<E>1;
														$<E->type>$ = dtype;
														value_s* v = make_value(VAR,dtype,NULL);		// A function present in 'hashtable.h'
														if( st.save_id( $<E->var>1 , v ) == 0)
														{
															yyerror("Variable already declared!");
															/*YYABORT;*/
														}

													}
					| declarator '[' conditional_expression ']'
					| declarator '[' ']'
					| '(' declarator ')'
					| declarator '(' parameter_type_list ')' { value_s* v = make_value(FUNC,dtype,NULL);		// A function present in 'hashtable.h'
																 										 st.update_id($<E->var>1, v);									// A function present in 'symbol_table.cpp'
																										 $<E>$ = $<E>1;
																										 printf("func begin %s\n", $<E->var>$);
																									 }
					| declarator '(' identifier_list ')' 		{	value_s* v = make_value(FUNC,dtype,NULL);
																 										st.update_id($<E->var>1, v);
																										$<E>$ = $<E>1;
																										printf("func begin %s\n", $<E->var>$);
																									}
					| declarator '(' ')'										{	value_s* v = make_value(FUNC,dtype,NULL);
																 										st.update_id($<E->var>1, v);
																										$<E>$ = $<E>1;
																										printf("func begin %s\n", $<E->var>$);
																									}
					;

parameter_type_list	: parameter_list
										;

parameter_list: parameter_declaration
							| parameter_list ',' parameter_declaration
							;

parameter_declaration	: datatype declarator
											| datatype
											;

identifier_list	: IDENTIFIER
								| identifier_list ',' IDENTIFIER
								;

initializer	: assignment_expression	{$<E>$ = $<E>1;}
						| '{' initializer_list '}'
						| '{' initializer_list ',' '}'
						;

initializer_list: initializer
								| initializer_list ',' initializer
								;

statement	: compound_statement
					| expression_statement
					| selection_statement
					| iteration_statement
					| jump_statement
					| declaration
					;

compound_statement: start_scope '{' '}' { st.close_scope(); }
									| start_scope '{' statement_list '}'	{ st.close_scope(); }
									;

// An artificially created production that starts a new scope when curly braces are encountered
start_scope	:		{ st.new_scope(); }
						;


declaration_list: declaration
								| declaration_list declaration
								;

statement_list: statement
							| statement_list statement
							;

expression_statement: ';'
										| expression ';'
										;

/*	BRANCH STATEMENTS
	*	At the beginning of a branch statement, print a goto to a label that is printed at the end of the branch condition. A stack called 'label_s' is used to
	* store the labels to take of nested branch and looping statements.
*/
selection_statement	: if_expression statement	{ //printf("%s",$<E->var>2);
																								printf("L%d:\n",label_s.top());
																								label_s.pop();
																							 }		%prec NO_ELSE
										| if_expression statement ELSE {	printf("goto L%d\n",temp_label_no);
																											printf("L%d:\n",label_s.top());
																											label_s.pop();
																											label_s.push(temp_label_no++);
																									 } statement	{ //printf("%s",$<E->var>5);
																									 								printf("L%d:\n",label_s.top());
																																	label_s.pop();
																																} %prec ELSE
										;

// An artificially created rule that combines the " IF '(' expression ')' " statements of the if and if-else blocks
if_expression : IF '(' expression ')' { label_s.push(temp_label_no);
																				printf("ifFalse %s goto L%d\n",$<E->var>3,temp_label_no++);
																		 	}
							;

//LOOP STATEMENTS: Similar to the BRANCH STATEMENTS, uses a stack to print 'goto's and labels
iteration_statement	: while_expression statement { //printf("%s",$<E->var>2);
																									 printf("L%d:\n",label_s.top());
																									 label_s.pop();
																								  }
										| DO 			{ label_s.push(temp_label_no);
																printf("L%d:\n",temp_label_no++);
															} statement WHILE '(' expression ')' { printf("if %s goto L%d\n",$<E->var>6, label_s.top());
																																			label_s.pop();
																																		} ';'
										;

// An artificially created rule that prints the goto and does a push onto the stack once the expression following a while is parsed.
while_expression:	WHILE '(' expression ')' { label_s.push(temp_label_no);
																						printf("ifFalse %s goto L%d\n",$<E->var>3,temp_label_no++);
																					 }

jump_statement: CONTINUE ';'
							| BREAK ';'
							| RETURN ';'	{printf("return\n");}
							| RETURN expression ';' {printf("return %s\n", $<E->var>2);}
							;

translation_unit: external_declaration
								| translation_unit external_declaration
								;

external_declaration: function_definition {printf("func end\n\n");}
										| declaration
										;

function_definition	: datatype declarator declaration_list compound_statement	{$<E>$ = $<E>2;}
										| datatype declarator compound_statement									{$<E>$ = $<E>2;}
										| declarator declaration_list compound_statement					{$<E>$ = $<E>1;}
										| declarator compound_statement														{$<E>$ = $<E>1;}
										;

%%
#include"lex.yy.c"
#include<ctype.h>
#include <stdio.h>

void yyerror(char *s) {
	printf("\nLine %d : %s\n", (yylineno), s);
}

int main(int argc, char *argv[])
{
	yyin = fopen(argv[1], "r");
	//st = new sym_table();

  if(!yyparse())
		printf("\nParsing complete\n");
	else
		printf("\nParsing failed\n");
	fclose(yyin);
	return 0;
}

extern char *yytext;
