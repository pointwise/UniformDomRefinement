#
# Copyright 2015-2019 (c) Pointwise, Inc.
# All rights reserved.
#
# This sample Pointwise script is not supported by Pointwise, Inc.
# It is provided freely for demonstration purposes only.
# SEE THE WARRANTY DISCLAIMER AT THE BOTTOM OF THIS FILE.
#

###############################################################################
# Uniformly refine unstructured domains
###############################################################################

package require PWI_Glyph 2
pw::Script loadTk

# Globals
set availDomNames [list]
set entList [list]
set entColors [list]
set entColorModes [list]
set entLineWidths [list]
set connList [list]
set connColors [list]
set connColorModes [list]
set connLineWidths [list]
set tempName ""
set origConns [list]

# Options
set opt(Method) edgeRefineDomain
set opt(Steps) 1
set opt(StepsMax) 10
set opt(Smooth) 0
set opt(DeleteOld) 0
set opt(Fate) CreateHere
set opt(MoveLayer) [pw::Display getCurrentLayer]

set color(Valid)    SystemWindow
set color(Invalid)  MistyRose

# Widget hierarchy
set w(LabelTitle)           .title
set w(FrameMain)            .main
set   w(FramePick)            $w(FrameMain).pick
set     w(FramePickButtons)     $w(FramePick).buttons
set       w(ButtonPick)           $w(FramePickButtons).bPick
set       w(ButtonClear)          $w(FramePickButtons).bClear
set     w(LabelPick)            $w(FramePick).label
set     w(ListPick)             $w(FramePick).lbPick
set     w(PickListScrollY)      $w(FramePick).scrollPick
set   w(FrameOpts)            $w(FrameMain).opts
set     w(FrameMethod)          $w(FrameOpts).method
set       w(RadioEdge)            $w(FrameMethod).rEdge
set       w(RadioCentroid)        $w(FrameMethod).rCentroid
set     w(FrameSteps)           $w(FrameOpts).steps
set       w(LabelSteps)           $w(FrameSteps).label
set       w(EntrySteps)           $w(FrameSteps).numSteps
set     w(CheckSmooth)          $w(FrameOpts).cbSmooth
set     w(CheckDeleteOld)       $w(FrameOpts).cbDeleteOld
set     w(FrameFate)            $w(FrameOpts).fate
set       w(RadioHere)            $w(FrameFate).rHere
set       w(RadioMove)            $w(FrameFate).rMove
set w(FrameButtons)         .buttons
set   w(Logo)                 $w(FrameButtons).logo
set   w(ButtonOK)             $w(FrameButtons).bOk
set   w(ButtonApply)          $w(FrameButtons).bApply
set   w(ButtonCancel)         $w(FrameButtons).bCancel


# Open file in temporary location for saving refined mesh
proc getTempFileName {} {
  global tempName
  set tmpdir [pwd]
  if {[file exists "/tmp"]} {set tmpdir "/tmp"}
  catch {set tmpdir $::env(TMP)}
  catch {set tmpdir $::env(TEMP)}
  set tempName [file join $tmpdir "pw_temp.stl"]
}


# Write triangle cell to STL file
proc writeStlCell {pts i0 i1 i2 tempChannel} {
  set u [pwu::Vector3 subtract [lindex $pts $i1] [lindex $pts $i0]]
  set v [pwu::Vector3 subtract [lindex $pts $i2] [lindex $pts $i0]]
  set normal [pwu::Vector3 normalize [pwu::Vector3 cross $u $v]]  
  puts $tempChannel [format "facet normal %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x $normal] \
    [pwu::Vector3 y $normal] \
    [pwu::Vector3 z $normal]]
  puts $tempChannel "  outer loop"
  puts $tempChannel [format "    vertex %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x [lindex $pts $i0]] \
    [pwu::Vector3 y [lindex $pts $i0]] \
    [pwu::Vector3 z [lindex $pts $i0]]]
  puts $tempChannel [format "    vertex %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x [lindex $pts $i1]] \
    [pwu::Vector3 y [lindex $pts $i1]] \
    [pwu::Vector3 z [lindex $pts $i1]]]
  puts $tempChannel [format "    vertex %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x [lindex $pts $i2]] \
    [pwu::Vector3 y [lindex $pts $i2]] \
    [pwu::Vector3 z [lindex $pts $i2]]]
  puts $tempChannel "  endloop"
  puts $tempChannel "endfacet"
}


# Refine a domain by connecting each cell's centroid to its vertices
proc centroidRefineDomain {dom tempChannel} {
  puts $tempChannel "solid [$dom getName]"
  set cellCount [$dom getCellCount]
  set quadWarned false
  for {set c 1} {$c <= $cellCount} {incr c} {
    set cell [$dom getCell $c]
    # Get cell vertices and centroid
    set nln [llength $cell]
    set centroid [pwu::Vector3 zero]
    set pts [list]
    foreach node $cell {
      set pt [$dom getXYZ -grid $node]
      set centroid [pwu::Vector3 add $centroid $pt]
      lappend pts $pt
    }
    set centroid [pwu::Vector3 divide $centroid $nln]
    lappend pts $centroid

    # Generate new cells
    if {3 == $nln} {
      for {set i 0} {$i < $nln} {incr i} {
        # Compute new cell unit normal
        set i1 [expr ($i + 1) % $nln]
        writeStlCell $pts $i $i1 end $tempChannel
      }
    } elseif {!$warned} {
      puts "Currently, refining quads is unsupported"
      set quadWarned true
    }
  }
  puts $tempChannel "endsolid [$dom getName]"
}


# Refine a domain by splitting each cell's edges at their midpoints
proc edgeRefineDomain {dom tempChannel} {
  puts $tempChannel "solid [$dom getName]"
  set cellCount [$dom getCellCount]
  set quadWarned false
  for {set c 1} {$c <= $cellCount} {incr c} {
    set cell [$dom getCell $c]
    # Get cell vertices and midpoints
    set nln [llength $cell]
    set pts [list]
    foreach node $cell {
      lappend pts [$dom getXYZ -grid $node]
    }
    for {set i 0} {$i < $nln} {incr i} {
      set i1 [expr ($i + 1) % $nln]
      lappend pts [pwu::Vector3 scale \
        [pwu::Vector3 add [lindex $pts $i] [lindex $pts $i1]] 0.5]
    }

    # Generate new cells
    if {3 == $nln} {
      for {set i 0} {$i < $nln} {incr i} {
        set i1 [expr $i + 3]
        set i1_0 [expr $i1 % 3]
      }
      writeStlCell $pts 0 3 5 $tempChannel
      writeStlCell $pts 1 4 3 $tempChannel
      writeStlCell $pts 2 5 4 $tempChannel
      writeStlCell $pts 3 4 5 $tempChannel
    } elseif {!$warned} {
      puts "Currently, refining quads is unsupported"
      set quadWarned true
    }
  }
  puts $tempChannel "endsolid [$dom getName]"
}


# Refine domains and write refined domains to temp file
proc refineAndWrite {} {
  global opt entList tempName
  getTempFileName
  set tempChannel [open $tempName w]
  foreach ent $entList {
    if {[$ent isOfType pw::DomainUnstructured]} {
      $opt(Method) $ent $tempChannel
    } elseif {[$ent isOfType pw::BlockUnstructured]} {
      # Future Enhancement: refine blocks
      puts "Currently, refining blocks is unsupported"
    } else {
      puts "Unsupported entity chosen for refinement: [$ent getName]"
    }
  }
  close $tempChannel
}


# Define db entities associated with each domain
set dbProjEnts [list]
proc defineDBProjEnts {} {
  global entList dbProjEnts
  foreach ent $entList {
    lappend dbProjEnts [$ent getDatabaseEntities -solver]
  }
}


# Define connectors associated with each original domain
proc defineOriginalConnectors {} {
  global entList origConns
  set origConns [list]
  foreach ent $entList {
    set edgeCount [$ent getEdgeCount]
    set conns [list]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set connCount [$edge getConnectorCount]
      for {set c 1} {$c <= $connCount} {incr c} {
        lappend conns [$edge getConnector $c]
      }
    }
    set conns [lsort -unique $conns]
    lappend origConns $conns
  }
}


# Project domains (interior only) onto db surfaces
proc projectCurrentDomains {} {
  global entList dbProjEnts
  set idx 0
  set mod [pw::Application begin Modify $entList]
  foreach ent $entList {
    if {0 < [llength [lindex $dbProjEnts $idx]] } {
      set projEnts [list]
      foreach dbEnt [lindex $dbProjEnts $idx] {
        if {[$dbEnt isSurface] && [$dbEnt isBaseForProject]} {
          lappend projEnts $dbEnt
        }
      }
      puts "[$ent getName] : $projEnts"
      pw::GridEntity project -interior $ent $projEnts
      incr idx
    }
  }
  $mod end
}


# Match connectors on imported domains to correspond with connectors on
# original domains
proc matchOriginalConnectors {refStep} {
  global entList origConns opt

  set tol [pw::Grid getNodeTolerance]

  # Split new connectors at endpoints of original connectors
  set domCount [llength $entList]
  for {set d 0} {$d < $domCount} {incr d} {
    set ent [lindex $entList $d]
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set connsToSplit [list]
      set connCount [$edge getConnectorCount]
      for {set c 1} {$c <= $connCount} {incr c} {
        lappend connsToSplit [$edge getConnector $c]
      }
      foreach con $connsToSplit {
        set splitLocs [list]
        foreach origCon [lindex $origConns $d] {
          $con closestPoint -parameter par0 -distance dist \
            [[$origCon getNode Begin] getPoint]
          if {$dist < $tol && $par0 > $tol && [expr 1.0 - $par0] > $tol} {
            lappend splitLocs $par0
          }
          $con closestPoint -parameter par1 -distance dist \
            [[$origCon getNode End] getPoint]
          if {$dist < $tol && $par1 > $tol && [expr 1.0 - $par1] > $tol} {
            lappend splitLocs $par1
          }
        }
        if [llength $splitLocs] {
          set splitLocs [lsort -unique $splitLocs]
          if {[catch {$con split $splitLocs}]} {
            puts "Warning: Could not split [$con getName]. ($splitLocs)"
            exit 1
          }
        }
      }
    }
  }

  # Join connectors at points that are not original endpoints
  for {set d 0} {$d < $domCount} {incr d} {
    set ent [lindex $entList $d]
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      for {set c 1; set connCount [$edge getConnectorCount]} \
            {$c <= $connCount && $connCount > 1} \
            {incr c; set connCount [$edge getConnectorCount]} {
        set con0 [$edge getConnector $c]
        set con1 [$edge getConnector [expr ($c % $connCount) + 1]]
        # Find shared node
        set n00 [$con0 getNode Begin]
        set n01 [$con0 getNode End]
        set n10 [$con1 getNode Begin]
        set n11 [$con1 getNode End]
        if {[$n00 equals $n10]} {
          set sharedNode $n00
        } elseif {[$n00 equals $n11]} {
          set sharedNode $n00
        } elseif {[$n01 equals $n10]} {
          set sharedNode $n01
        } elseif {[$n01 equals $n11]} {
          set sharedNode $n01
        }
        # Find a matching original endpoint
        set doJoin yes
        foreach origCon [lindex $origConns $d] {
          if {[[$origCon getNode Begin] equals $sharedNode]} {
            set doJoin no
            break
          }
          if {[[$origCon getNode End] equals $sharedNode]} {
            set doJoin no
            break
          }
        }
        if {$doJoin} {
          if {[catch {$con0 join $con1}]} {
            puts "Warning: Could not join [$con0 getName] and [$con1 getName]"
          }
        }
      }
    }
  }

  # Recreate definitions of new connectors to match old connectors on db curves
  set newConns [list]
  for {set d 0} {$d < $domCount} {incr d} {
    set origDomConns [lindex $origConns $d]
    set ent [lindex $entList $d]
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set newConnCount [$edge getConnectorCount]
      for {set i 1} {$i <= $newConnCount} {incr i} {
        set newCon [$edge getConnector $i]
        if {-1 != [lsearch $newConns $newCon]} {
          continue
        }
        lappend newConns $newCon
        set modifyMode [pw::Application begin Modify [list $newCon]]
        set newBeg [$newCon getNode Begin]
        set newEnd [$newCon getNode End]
        # Find matching original connector
        set matchIdx -1
        set flipOrient false
        set minDist 1.0e10
        set origConnCount [llength $origDomConns]
        for {set c 0} {$c < $origConnCount} {incr c} {
          set origCon [lindex $origDomConns $c]
          set origBeg [$origCon getNode Begin]
          set origEnd [$origCon getNode End]
          if {[$newBeg equals $origBeg] && [$newEnd equals $origEnd]} {
            set newX1 [$newCon getXYZ -grid 3]
            set origX1 [$origCon getXYZ -grid 2]
            set dist [pwu::Vector3 length \
              [pwu::Vector3 subtract $newX1 $origX1]]
            if {$dist < $minDist} {
              set matchIdx $c
              set minDist $dist
              set flipOrient false
            }
          } elseif {[$newBeg equals $origEnd] && [$newEnd equals $origBeg]} {
            set newConDim [$newCon getDimension]
            set newX1 [$newCon getXYZ -grid [expr $newConDim - 2]]
            set origX1 [$origCon getXYZ -grid 2]
            set dist [pwu::Vector3 length \
              [pwu::Vector3 subtract $newX1 $origX1]]
            if {$dist < $minDist} {
              set matchIdx $c
              set minDist $dist
              set flipOrient true
            }
          }
        }
        if {-1 == $matchIdx} {
          puts "Warning: Could not find original match for [$newCon getName]"
          $modifyMode end
          continue
        }
        set origCon [lindex $origDomConns $matchIdx]
        set origDomConns [lreplace $origDomConns $matchIdx $matchIdx]
        if {$flipOrient} {
          $newCon setOrientation IMaximum
        }
        # Copy segment definitions
        set segs [list]
        set origSegCount [$origCon getSegmentCount]
        for {set s 1} {$s <= $origSegCount} {incr s} {
          lappend segs [$origCon getSegment -copy $s]
        }
        $newCon replaceAllSegments $segs
        $newCon setLayer $opt(MoveLayer)
        $modifyMode end
      }
    }
  }
}


# Refine all entities in entList
proc refineAll {} {
  global w opt entList tempName

  if {0 == [llength $entList ]} {
    return
  }

  defineDBProjEnts
  defineOriginalConnectors

  for {set refStep 1} {$refStep <= $opt(Steps)} {incr refStep} {
    refineAndWrite
    
    # Import grid from temp file
    set entList [pw::Grid import -type STL $tempName]
    
    # Fix imported grid
    matchOriginalConnectors $refStep
    projectCurrentDomains
    # Future Enhancement: Rename new doms and cons to correspond to originals
    # (something like *-refined-<level>)

    # Move refined entities to different layer
    if {$opt(Fate) == {CreateMove}} {
      foreach ent $entList {
        $ent setLayer $opt(MoveLayer)
      }
      if {$opt(MoveLayer) < [expr [pw::Layer getCount] -1]} {
        incr opt(MoveLayer)
      }
    }

    # Smooth refined entities
    if {$opt(Smooth)} {
      set solver [pw::Application begin UnstructuredSolver $entList]
      $solver run Smooth
      $solver end
    }

    pw::Display update
  }
}


# Select entities from Pointwise GUI
proc selectEntities {} {
  global w entList

  resetRenderAtts

  if {[pw::Grid getCount -type pw::DomainUnstructured] > 0} {
    wm withdraw .
    pw::Display selectEntities -description "Select entities for refinement."\
      -selectionmask [pw::Display createSelectionMask\
      -requireDomain Unstructured] \
      -preselect $entList \
      resultArray
    set entList $resultArray(Domains)
    $w(ListPick) selection clear 0 end
    foreach ent $entList {
      set entName [$ent getName]
      # Find name in listbox and mark that entry as selected
      for {set i 0} {$i < [$w(ListPick) size]} {incr i} {
        if {$entName == [$w(ListPick) get $i]} {
          $w(ListPick) selection set $i
        }
      }
    }
    if {[winfo exists .]} {
      wm deiconify .
    }
  } else {
    puts "Warning: No entities available for selection."
  }

  updateSelection
}


# Set the font for the title frame
proc setTitleFont { l } {
  global titleFont
  if { ! [info exists titleFont] } {
    set fontSize [font actual TkCaptionFont -size]
    set titleFont [font create -family [font actual TkCaptionFont -family] \
        -weight bold -size [expr {int(1.5 * $fontSize)}]]
  }
  $l configure -font $titleFont
}


# Update listbox with all available unstructured domains
proc updatePickList {} {
  global availDomNames
  set availDoms [pw::Grid getAll -type pw::DomainUnstructured]
  set availDomNames [list]
  foreach dom $availDoms {
    if {[pw::Display isLayerVisible [$dom getLayer]]} {
      lappend availDomNames [$dom getName]
    }
  }
}


# Reset gui entity coloring to original
proc resetRenderAtts {} {
  global entList entColors entColorModes entLineWidths \
    connList connColors connColorModes connLineWidths
  # Domains
  set entCount [llength $entList]
  for {set e 0} {$e < $entCount} {incr e} {
    set ent [lindex $entList $e]
    set fillMode [$ent getRenderAttribute FillMode]
    if {{Shaded} == $fillMode || {Flat} == $fillMode} {
      $ent setRenderAttribute SecondaryColor [lindex $entColors $e]
      $ent setRenderAttribute SecondaryColorMode [lindex $entColorModes $e]
    } else {
      $ent setColor [lindex $entColors $e]
      $ent setRenderAttribute ColorMode [lindex $entColorModes $e]
    }
    $ent setRenderAttribute LineWidth [lindex $entLineWidths $e]
  }
  set entColors [list]
  set entColorModes [list]
  set entLineWidths [list]
  # Connectors
  set connCount [llength $connList]
  for {set c 0} {$c < $connCount} {incr c} {
    set con [lindex $connList $c]
    $con setColor [lindex $connColors $c]
    $con setRenderAttribute ColorMode [lindex $connColorModes $c]
    $con setRenderAttribute LineWidth [lindex $connLineWidths $c]
  }
  set connColors [list]
  set connColorModes [list]
  set connLineWidths [list]
}


# Update list and gui with current selection
proc updateSelection {} {
  global w entList entColors entColorModes entLineWidths \
    connList connColors connColorModes connLineWidths

  set selection [$w(ListPick) curselection]
  set entList [list]
  set connList [list]
  foreach sel $selection {
    set name [$w(ListPick) get $sel]
    set ent [pw::GridEntity getByName $name]
    lappend entList $ent
    set fillMode [$ent getRenderAttribute FillMode]
    if {{Shaded} == $fillMode || {Flat} == $fillMode} {
      lappend entColors [$ent getRenderAttribute SecondaryColor]
      lappend entColorModes [$ent getRenderAttribute SecondaryColorMode]
      $ent setRenderAttribute SecondaryColor [list 1 1 1]
      $ent setRenderAttribute SecondaryColorMode Entity
    } else {
      lappend entColors [$ent getColor]
      lappend entColorModes [$ent getRenderAttribute ColorMode]
      $ent setColor [list 1 1 1]
      $ent setRenderAttribute ColorMode Entity
    }
    lappend entLineWidths [$ent getRenderAttribute LineWidth]
    $ent setRenderAttribute LineWidth 2
    # Get a list of all affected connectors
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set connCount [$edge getConnectorCount]
      for {set c 1} {$c <= $connCount} {incr c} {
        lappend connList [$edge getConnector $c]
      }
    }
  }

  #Change connector rendering
  set connList [lsort -unique $connList]
  foreach con $connList {
    # Save original attributes
    lappend connColors [$con getColor]
    lappend connColorModes [$con getRenderAttribute ColorMode]
    lappend connLineWidths [$con getRenderAttribute LineWidth]
    # Set new attributes
    $con setColor [list 1.0 1.0 1.0]
    $con setRenderAttribute ColorMode Entity
    $con setRenderAttribute LineWidth 2
  }
}


# Enable/Disable action buttons based on current settings
proc updateButtons {} {
  global w color
  if {[string equal -nocase [$w(EntrySteps) cget -background] $color(Valid)]} {
    $w(ButtonOK) configure -state normal
    $w(ButtonApply) configure -state normal
  } else {
    $w(ButtonOK) configure -state disabled
    $w(ButtonApply) configure -state disabled
  }
  update
}


# Validate the entry for number of steps
proc validateSteps {steps widgetKey} {
  global w color opt
  if {[string is integer -strict $steps] && \
        $steps >= 0 && $steps < $opt(StepsMax)} {
    $w($widgetKey) configure -background $color(Valid)
  } else {
    $w($widgetKey) configure -background $color(Invalid)
  }
  updateButtons
  return 1
}


# Apply selection that was made before the script was executed
proc getPreSelection {} {
  global w entList
  if {[pw::Display getSelectedEntities \
        -selectionmask [pw::Display createSelectionMask\
        -requireDomain Unstructured] \
        resultArray]} {
    set entList $resultArray(Domains)
    $w(ListPick) selection clear 0 end
    foreach ent $entList {
      set entName [$ent getName]
      # Find name in listbox and mark that entry as selected
      for {set i 0} {$i < [$w(ListPick) size]} {incr i} {
        if {$entName == [$w(ListPick) get $i]} {
          $w(ListPick) selection set $i
        }
      }
    }
  }
  updateSelection
  pw::Display update
}


# Build user interface
proc makeWindow {} {
  global w opt availDomNames entList

  updatePickList

  wm title . "Uniformly Refine"
  label $w(LabelTitle) -text "Uniformly Refine Grid Entities"
  setTitleFont $w(LabelTitle)

  frame $w(FrameMain)

  frame $w(FramePick)
  frame $w(FramePickButtons)
  button $w(ButtonPick) -text "Select From GUI" -command {
    selectEntities
    pw::Display update
  }
  button $w(ButtonClear) -text "Clear Selection" -command {
    resetRenderAtts
    set entList [list]
    $w(ListPick) selection clear 0 end
  }
  label $w(LabelPick) -text "Selected Entities:"
  listbox $w(ListPick) -height 10 -selectmode extended \
    -listvariable availDomNames \
    -yscrollcommand {$w(PickListScrollY) set}
  scrollbar $w(PickListScrollY) -command {$w(ListPick) yview}


  labelframe $w(FrameOpts) -text "Options"
  frame $w(FrameMethod)
  radiobutton $w(RadioEdge) -text "Refine at edge midpoints" \
    -value edgeRefineDomain -variable opt(Method)
  radiobutton $w(RadioCentroid) -text "Refine at element centroids" \
    -value centroidRefineDomain -variable opt(Method)
  frame $w(FrameSteps)
  label $w(LabelSteps) -text "Number of refinement steps:"
  entry $w(EntrySteps) -width 5 -bd 2 -textvariable opt(Steps)
  $w(EntrySteps) configure -validate key -vcmd {validateSteps %P EntrySteps}
  checkbutton $w(CheckSmooth) -text "Smooth refined entities at each step" \
    -variable opt(Smooth)
  frame $w(FrameFate)
  checkbutton $w(CheckDeleteOld) -text "Delete original entities"\
    -variable opt(DeleteOld)
  radiobutton $w(RadioHere) \
    -text "Create refined entities in current layer" \
    -value CreateHere -variable opt(Fate) \
    -command {set opt(MoveLayer) [pw::Display getCurrentLayer]}
  radiobutton $w(RadioMove) \
    -text "Create refined entities in successive empty layers" \
    -value CreateMove -variable opt(Fate) \
    -command {
      for {set l [expr [pw::Layer getCount] - 1]} {$l >= 0} {incr l -1} {
        if {[llength [pw::Layer getLayerEntities $l]] > 0} {
          set opt(MoveLayer) [expr $l + 1]
          break
        }
      }
    }

  frame $w(FrameButtons)
  button $w(ButtonCancel) -text "Cancel" -command {resetRenderAtts; exit}
  button $w(ButtonApply) -text "Apply" -command {
    wm withdraw .
    resetRenderAtts
    refineAll
    pw::Display update
    if {[winfo exists .]} {
      wm deiconify .
    }
    updatePickList
    updateSelection
  }
  button $w(ButtonOK) -text "OK" -command {
    $w(ButtonApply) invoke
    $w(ButtonCancel) invoke
  }
  label $w(Logo) -image [pwLogo] -bd 0 -relief flat

  pack $w(LabelTitle) -side top
  # Spacer
  pack [frame .spMain -bd 1 -height 2 -relief sunken] -side top -fill x -pady 5

  pack $w(FrameMain) -side top -fill both

  pack $w(FramePick)
  grid $w(LabelPick) -sticky w
  grid $w(ListPick) $w(PickListScrollY) $w(FramePickButtons) -sticky ns
  pack $w(ButtonPick) -fill x -padx 10 -pady 3
  pack $w(ButtonClear) -fill x -padx 10 -pady 3
  
  pack $w(FrameOpts) -side top -ipadx 3 -ipady 3
  pack $w(FrameMethod) -side top -fill x
  pack $w(RadioEdge) -side top -anchor w
  pack $w(RadioCentroid) -side top -anchor w
  pack [frame $w(FrameOpts).spOpts1 -bd 1 -height 2 -relief sunken] -side top\
    -fill x -pady 3
  pack $w(FrameSteps) -side top -fill x
  pack $w(LabelSteps) -side left
  pack $w(EntrySteps) -side left
  pack $w(CheckSmooth) -side top -anchor w
  pack $w(CheckDeleteOld) -side top -anchor w
  pack [frame $w(FrameOpts).spOpts2 -bd 1 -height 2 -relief sunken] -side top\
    -fill x -pady 3
  pack $w(FrameFate) -side top -fill x
  pack $w(RadioHere) -side top -anchor w
  pack $w(RadioMove) -side left

  pack $w(FrameButtons) -side bottom -fill x -ipadx 5 -ipady 2
  pack $w(ButtonCancel) -side right -padx 3
  pack $w(ButtonApply) -side right -padx 3
  pack $w(ButtonOK) -side right -padx 3
  pack $w(Logo) -side left -padx 3

  bind . <Key-Return> {$w(ButtonApply) invoke}
  bind . <Control-Key-Return> {$w(ButtonOK) invoke}
  bind . <Key-Escape> {$w(ButtonCancel) invoke}
  bind $w(ButtonOK) <Key-Return> {
    $w(ButtonOK) flash
    $w(ButtonOK) invoke
  }
  bind $w(ButtonApply) <Key-Return> {
    $w(ButtonApply) flash
    $w(ButtonApply) invoke
  }
  bind $w(ButtonCancel) <Key-Return> {
    $w(ButtonCancel) flash
    $w(ButtonCancel) invoke
  }
  # Reflect listbox selection in GUI
  bind $w(ListPick) <ButtonRelease> {
    resetRenderAtts
    updateSelection
    pw::Display update
  }
  bind $w(ListPick) <B1-Motion> {
    resetRenderAtts
    updateSelection
    pw::Display update
  }

  wm resizable . 0 0
}


proc pwLogo {} {
  set logoData "
R0lGODlhngAaAOfeACMfIBBfrRFfrRRgrhVhrhZhrhdhrhhhrhphrhhirhtjryJkryNkryhmsCpm
rytnsCxnsC1nsC9osDFpsTVqsTZrsTltsjxtsj1usj9usj9vsz9ws0Fws0Jws0VytEZytERztUdz
tEhztEp0tU53tkx4t094t1F5tlJ5tlJ5t1R6t1Z7t1d8uFl9uF1/uWWFvGeFvGWGvGiHvWuKvmuK
v22KvnKNv3OOwHWQwXaQwHaRwXiSwXuUwnyUwn6Vw3+Ww36XxIGXxICYxIGYxIGZxYOaxYecxoid
xoqex4ufyI6hyJCjypGkypCly5Wny5epzZqrzZqrzp2tzp2tz6Cv0KCw0KGx0aKx0aOy0aSz0qWz
0aWz0qW00qa00qi206m31Ku41ay51ay61q261a271q6816+81rC917G+2LK+2LO/2bTA2bTB2rXB
2bXB2rbC2rfC2rjD27jE27nE27nE3LrE27rF3LvF3LzG3bvH3b3H3b7H3b7I3r/I3sHK38HL38LM
4MPM38PN4cXN4MXN4cPO4cbO4cbP4cfP4sfQ4sjQ4sjR48rS48rS5MrT5MvT5MzT48zU5M7V5c/W
5s/X5tDX5tHX59HY59LZ59LZ6NPZ59Pa6NXb6dTc6dbc6dbd6tfd6tje6tje69jf7Nrf69vh7dzh
7dzi7t3i7d3j7t7j7d/k7t/k7+Dl7+Hl7+Hm7+Hm8OLm7+Lm8OLn8OPn8OPo8eTo8eXp8ebq8ufq
8ufr8ufr8+ns8+nt9Oru9Oru9evu9Ovu9evv9ezv9ezw9u3w9u7w9u7x9u7x9+/x9+7y9+/y9/Dy
9+/z+PDz+PHz+PL0+PP1+fT3+vX3+/f4+/f5+/f5/Pj5+/n6/Pr7/fz8/fz9/v7+/v7+////////
////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////yH5BAEKAP8ALAAAAACeABoA
AAj+AP8JHEiwoMGDCBMqXMiwocOHECNKnEixosWLGBUC+LdxIICPIEN2VNgEzyZg2zzp0ZFQpECR
MD8SjEnzZciDI2e6dKkTZEuaMV/iBOrzYJFjx9Cw4VWCR5phgSIMLUr0ps2qMjla1Tk1K0+PWw1i
3bqx7FWiB9f0KkNtWbdlbQoEgJCIkwGxVsd61Xs2K1i8ecNqLdoVq0eOiAdXLXjo2BNitk51ymKN
ValRjKiRIRCg516+ekd+vVoQZt/Sgj0bTpyT78BguSRt60XN27ZGW5TFqJEkzbZjc1T3XRwaLGHF
qAmPVuw3+djDOZnXFKjh2IocsBRl8yasmBthAcL+B3hmAk4045+fF0cvmuzX5UEzQvzK5U8AJdzq
UMrz6sQqalGIt0wDAaywyWnMAdbcfO4pF9Zy0snHYFEBWIIEC748swMyFKwiCC86oFJJBh78It4e
CEIIoUOmRZgge4VFJ6F08QWQCg2xTBHEMNdoAo0zIwRwwBq62AGIeHKkmJqKqQkXYYsIOnfccNP9
tFoAmHzCSHhSXDLEBrjYIB4W3hAh3iCPvMjklC8i9B5aTip4XGgyqgbUP+F9cY0I4Z0RRnhTTBKe
BKg04osK4bUChJpLNsqmlFQKtiKV7C1mJZzhgaGND+EZ8kR4DAzjggqr0BEAFbRMgIIwBTDK5pr+
C8pZ6atNzhpplTHGR0IAqlhRTBUIQLKEeGLIUgwV4vGxiB5qdMYTrDJO6uSdkGr07HpuwjnQA84c
4AImwRhzSBdwhLJMNTOIF8ACriCDgbOB0SpvrLJGWq+1VLl2aZ0EFdKKeCk4IsobXvyQQBt3qFvB
Lcl8oOS80dYaZ3zV4usTlBFJK9A2pKirhR7qhoDMBeFdgMoaaUTycKzQNnTtihoP56JEMf9TjRHi
CbGJugH4YUYAMNyihgAOmLJyxBC73CC9be5bVs3ZPlqQNLz00UEAFizDcwvFxFEME+LB2HSUYjO0
NL8xt4jxhEwXBMIcyBByxC4vhEcCE4xgAwp9B2GL3XLFCz3Y9mjP0Uht1G0XFIAGV2TCzDTMNJNL
JFDg0MsA4VX7d5yBLyh104XTaTG/B4knQy0KCKDuJk50prmjLEuM1+yIt2ap4bje25B4s9zAcw+u
FEb28GNrhNPodhKOrfASjYEIz/sSv/mMZeMu5+3UZ6/99twnFBAAOw=="

  return [image create photo -format GIF -data $logoData]
}

makeWindow
getPreSelection
::tk::PlaceWindow . widget
tkwait window .

#
# DISCLAIMER:
# TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, POINTWISE DISCLAIMS
# ALL WARRANTIES, EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED
# TO, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE, WITH REGARD TO THIS SCRIPT.  TO THE MAXIMUM EXTENT PERMITTED 
# BY APPLICABLE LAW, IN NO EVENT SHALL POINTWISE BE LIABLE TO ANY PARTY 
# FOR ANY SPECIAL, INCIDENTAL, INDIRECT, OR CONSEQUENTIAL DAMAGES 
# WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF 
# BUSINESS INFORMATION, OR ANY OTHER PECUNIARY LOSS) ARISING OUT OF THE 
# USE OF OR INABILITY TO USE THIS SCRIPT EVEN IF POINTWISE HAS BEEN 
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGES AND REGARDLESS OF THE 
# FAULT OR NEGLIGENCE OF POINTWISE.
#
