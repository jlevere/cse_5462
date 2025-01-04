# OSU Undergraduate Class SP '25 - CSE 5462

## Network Programming

This is an elective - focused on network programming

This course focuses on learning socket programming on real networks. 

*Course Level:* Undergraduate/Graduate

*Units:* 3

*Instructors:* Dr. David Ogle <David.ogle@ucdenver.edu> <ogle.87@osu.edu>

*Instruction Mode:* Online

*Lectures:* Tue and Thu, 15:55 – 17:15 Zoom

*Office Hours:* Wed 17:30-18:30 [UC Den Zoom Office Hours](https://ucdenver.zoom.us/my/daveogle)


## Repo info

This repo is a personal monorepo for the class, but the class is actually comprised of a repo for each assignemnt under a github classroom org for the semester.

To help this clean, I am using subtree with each of the assignment repos grafted into my monorepo.  This alows for me to work in the monorepo but then push things to their correct repo for the class.

The commands for this:

`git remote add lab0 git@github.com:CSE-5462-OSU-Spring2025/lab0-jLevere.git`

`git subtree push --prefix=lab0 lab0 main`

Where `lab0` is the name of the remote repo and `lab0/` is the monorepo location for it.  This works quite nicely.