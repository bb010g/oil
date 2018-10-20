#!/usr/bin/env python
"""
main_loop.py

Two variants:

main_loop.Interactive()
main_loop.Batch()

They call CommandParser.ParseLogicalLine() and Executor.ExecuteAndCatch().

Get rid of:

ex.Execute() -- only used for tests
ParseWholeFile() -- needs to check the here doc.
"""
from __future__ import print_function

from core import ui
from core import util
from osh.meta import ast

log = util.log


def Interactive(opts, ex, c_parser, arena):
  status = 0
  while True:
    # Reset internal newline state.  NOTE: It would actually be correct to
    # reinitialize all objects (except Env) on every iteration.
    c_parser.Reset()
    c_parser.ResetInputObjects()

    try:
      node = c_parser.ParseLogicalLine()
    except util.ParseError as e:
      ui.PrettyPrintError(e, arena)
      # NOTE: This should set the status interactively!  Bash does this.
      status = 2
      continue

    if node is None:  # EOF
      # NOTE: We don't care if there are pending here docs in the interative case.
      break

    is_control_flow, is_fatal = ex.ExecuteAndCatch(node)
    status = ex.LastStatus()
    if is_control_flow:  # e.g. 'exit' in the middle of a script
      break
    if is_fatal:  # e.g. divide by zero 
      continue

    # TODO: Replace this with a shell hook?  with 'trap', or it could be just
    # like command_not_found.  The hook can be 'echo $?' or something more
    # complicated, i.e. with timetamps.
    if opts.print_status:
      print('STATUS', repr(status))

  if ex.MaybeRunExitTrap():
    return ex.LastStatus()
  else:
    return status  # could be a parse error


def Batch(ex, c_parser, arena, nodes_out=None):
  """Loop for batch execution.

  Args:
    nodes_out: if set to a list, the input lines are parsed, and LST nodes are
      appended to it instead of executed.  For 'sh -n'.

  Can this be combined with interative loop?  Differences:
  
  - Handling of parse errors.
  - Have to detect here docs at the end?

  Not a problem:
  - Get rid of --print-status and --show-ast for now
  - Get rid of EOF difference

  TODO:
  - Do source / eval need this?
    - 'source' needs to parse incrementally so that aliases are respected
    - I doubt 'eval' does!  You can test it.
  - In contrast, 'trap' should parse up front?
  - What about $() ?
  """
  status = 0
  while True:
    try:
      node = c_parser.ParseLogicalLine()  # can raise ParseError
      if node is None:  # EOF
        c_parser.CheckForPendingHereDocs()  # can raise ParseError
        break
    except util.ParseError as e:
      ui.PrettyPrintError(e, arena)
      status = 2
      break

    if nodes_out is not None:
      nodes_out.append(node)
      continue

    #log('parsed %s', node)

    is_control_flow, is_fatal = ex.ExecuteAndCatch(node)
    status = ex.LastStatus()
    # e.g. divide by zero or 'exit' in the middle of a script
    if is_control_flow or is_fatal:
      break

  if ex.MaybeRunExitTrap():
    return ex.LastStatus()
  else:
    return status  # could be a parse error


def ParseWholeFile(c_parser):
  """Parse an entire shell script.

  This uses the same logic as Batch().
  """
  children = []
  while True:
    node = c_parser.ParseLogicalLine()  # can raise ParseError
    if node is None:  # EOF
      c_parser.CheckForPendingHereDocs()  # can raise ParseError
      break
    children.append(node)

  if len(children) == 1:
    return children[0]
  else:
    return ast.CommandList(children)
