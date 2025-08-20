require_relative "../../factories/rubric_factory"
require_relative "../../factories/rubric_association_factory"

require_relative "./common"
require_relative "./utils"
require 'json'
require 'yaml'
require 'securerandom'

def generate_custom_course
  puts "Generating custom course"
  @student_list = []
  @enrollment_list = []
  @course_name = "Custom Course By Alex w/Discussion"
  course_with_teacher(
    account: @root_account,
    active_course: 1,
    active_enrollment: 1,
    course_name:@course_name,
    name: "Robot Alex 2"
  )
  @teacher = @user
  @teacher.pseudonyms.create!(
    unique_id: "newteacher#{@teacher.id}@example.com",
    password: "password",
    password_confirmation: "password"
  )
  @teacher.email = "newteacher#{@teacher.id}@example.com"
  @teacher.accept_terms
  @teacher.register!
  puts "Successfully generated custom course!"

  puts "Adding a student"

  course_with_student(
    account: @root_account,
    active_all: 1,
    course: @course,
    name: "Da Student"
  )

  @enrollment_list << @enrollment
  email = "daStudent#{SecureRandom.alphanumeric(10)}@ualberta.ca"
  @user.pseudonyms.create!(
    unique_id: email,
    password: "password",
    password_confirmation: "password"
  )
  @user.email = email
  @user.accept_terms
  @student_list << @user

  puts @course

  @student = @user

  @topic = @course.discussion_topics.create!(title: "A class discussion", message: "I'd like us to have a discussion.", user: @teacher, discussion_type: "threaded")
  @root_reply = @topic.reply_from(user: @student, text: "Sure!")
  @teacher_reply = @root_reply.reply_from(user: @teacher, text: "Thanks!")

  @all_entries = [@root_reply, @teacher_reply]
  @all_entries.each(&:reload)

  @topic.reload



end


def generate_test_environment

  puts "Loading test data from container path: /usr/src/app/spec/fixtures/data_generation/test_data.yaml"
  
  test_data = YAML.load_file "/usr/src/app/spec/fixtures/data_generation/test_data.yaml"

  output = [] # Holds task instance output data

  courses = [] # Holds the generated course objects


  test_data["courses"].each {|course| 
    test_course = TestCourse.new({
      :course_name => course["name"],
      :course_code => course["code"],
      :unused_group_names => course["unused_group_names"],
      :unused_announcements => course["unused_announcements"],
      :unused_discussions => course["unused_discussions"],
      :teacher_name => course["instructor"]["name"],
      :teacher_email => course["instructor"]["email"],
      :teacher_password => course["instructor"]["password"],
      :student_name => course["main_user"]["name"],
      :student_email => course["main_user"]["email"],
      :student_password => course["main_user"]["password"]
    })
    courses << test_course
  }


  # Create resources for each course
  courses.each { |_course|
    course_data = test_data["courses"].select {|course| course["name"] == _course.course.name}
    course_data = course_data[0]

    # Fetch student test data and create enrolled students
    course_data["students"].each { |student|
      puts "Creating student #{student["name"]} in #{_course.course.name}"

      _course.create_classmate({
        :student_email => student["email"],
        :student_name => student["name"],
        :student_password => student["password"]
      })

    }

    # Fetch group category test data and create these in anticipation of creating groups
    if course_data["group_categories"]
      course_data["group_categories"].each {|group_category|
        _course.create_group_category(group_category)
      }
    end


    # Fetch group test data and create student groups
    course_data["groups"].each { |group|
      puts "Creating group '#{group["name"]}' in #{_course.course.name}"
       _course.create_group(group)
    }

    # Fetch page test data and create pages for the course
    course_data["pages"].each {|page|
      _course.create_page(page)
    }

    # Fetch discussion test data and create discussions for the course.
    course_data["discussions"].each { |discussion|
      puts "Creating discussion '#{discussion["title"]}' in  #{_course.course.name}"
      _course.create_discussion(discussion)
    }

    # Fetch announcement test data and create announcements
    course_data["announcements"].each {|announcement|

      puts "Creating announcement '#{announcement["title"]}' in #{_course.course.name}"

      _course.create_announcement(announcement)


    }

    # Fetch assignment test data and create assignments
    course_data["assignments"].each { |assignment|
      puts "Creating assignment #{assignment["title"]} in #{_course.course.name}"

      if assignment["submission_types"].include?("discussion_topic")
        _course.create_discussion_assignment(assignment)
        next
      end

      assignment_opts = _course.default_assignment_opts
      assignment_opts[:title] = assignment["title"]
      assignment_opts[:description] = assignment["description"]
      assignment_opts[:due_at] = assignment["due_at"]
      assignment_opts[:points_possible] = assignment["points_possible"]
      assignment_opts[:created_at] = assignment["created_at"]
      assignment_opts[:updated_at] = assignment["updated_at"]
      assignment_opts[:submission_types] = assignment["submission_types"]

      a = _course.create_assignment(assignment_opts)

      # Create a dummy rubric for the assignment
      rubric_opts = {
        :context => _course.course,
        :title => "Rubric for #{assignment["title"]}",
        :data => larger_rubric_data
      }
      rubric = rubric_model(rubric_opts)
      rubric.save!
      rubric.reload

      a.build_rubric_association(
        rubric: rubric,
        purpose: "grading",
        use_for_grading: true,
        context: _course.course
      )
      a.rubric_association.save!
      a.reload
      a.save!

      # Populate assignment submissions
      if assignment["submissions"] # If the assignment has submissions, create those too.
        assignment["submissions"].each { |submission|
          submission["user"] = _course.resolve_user_value(submission["user"], _course)
          _submission = a.submit_homework(submission["user"], submission.except("user"))

          if submission["peer_review"] # If there are peer review or instructor feedback comments create those too!
            submission["peer_review"].each { |review|
              review["author"] = _course.resolve_user_value(review["author"], _course)
              _submission.add_comment(comment: review["comment"], author: review["author"])
            }
          end

          _submission.save!

          # If there is instructor feedback for the submission let's create it now.
          if submission["feedback"]
            feedback = submission["feedback"]
            
            # Resolve the grader string from the test data to an actual user account
            feedback["grader"] = _course.resolve_user_value(feedback["grader"], _course)
            
            if feedback["grade"] # If a grade is specified, assign that grade to the submission  
              a.grade_student(submission["user"], grade: feedback["grade"], grader: feedback["grader"])
            end
            
            if feedback["comment"] # If there is a feedback comment add it to the submission
              _submission.add_comment(comment: feedback["comment"], author: feedback["grader"])
            end

          end
        }
      end

      if assignment["peer_reviews"] # If the assignment has peer reviews enabled, set those up.
        a.peer_review_count = assignment["peer_reviews"]["count"]
        a.automatic_peer_reviews = assignment["peer_reviews"]["automatic_peer_reviews"]
        a.update!(peer_reviews: true)
        a.save!
        result = a.assign_peer_reviews
      end

    }



    # Fetch quiz test data and create quizzes
    quiz_data = course_data["quizzes"]
    quiz_data.each { |quiz|
      
      puts "Creating quiz #{quiz["title"]} in #{_course.course.name}"

      if quiz["rubric"]
        @quiz = assignment_quiz([], {
          :course=> _course.course,
          :title => quiz["title"],
          :description => quiz["description"],
          :due_at => quiz["due_at"],
          :submission_types => ['online_quiz'],
          :workflow_state => quiz["workflow_state"]
        })

        

        
        # Create the rubric
        puts "Creating rubric #{quiz["rubric"]["title"]} for #{_course.course.name}"

        rubric_opts = quiz["rubric"].merge({
          :user=>_course.teacher,
          :context=>_course.course
        })
        
        rubric = rubric_model(rubric_opts)
        rubric.save!
        rubric.reload

        @assignment.build_rubric_association(
          rubric: rubric,
          purpose: "grading",
          use_for_grading: true,
          context: _course.course
        )
        @assignment.rubric_association.save!
        @assignment.reload
        @assignment.save!

                
        # Populate quiz questions
        questions = []
        quiz["questions"].each { |question|
          question[:regrade_option] = false
        }

        quiz["questions"].each { |question_data|
          question = @quiz.quiz_questions.create!(question_data: question_data)
          questions << question
        }
        @quiz.generate_quiz_data
        @quiz.due_at = quiz["due_at"]

        if quiz["one_question_at_a_time"]
          @quiz.one_question_at_a_time = true
          @quiz.save!
        end

        if quiz["allowed_attempts"]
          @quiz.allowed_attempts = quiz["allowed_attempts"]
          @quiz.save!
        end

        @quiz.save!
        @quiz.publish!

        _course.quizzes << @quiz

      else

        quiz_opts = quiz.except("rubric", "questions")

        q = _course.course.quizzes.create!(quiz_opts) # Create the actual quiz

        if quiz["one_question_at_a_time"]
          puts "ONE QUESTION AT A TIME!"
          q.one_question_at_a_time = true
          q.save!
        end

        if quiz["allowed_attempts"]
          q.allowed_attempts = quiz["allowed_attempts"]
          q.save!
        end
        
        # Populate quiz questions
        questions = []
        
        quiz["questions"].each { |question|
          question[:regrade_option] = false
        }

        quiz["questions"].each { |question_data|
          question = q.quiz_questions.create!(question_data: question_data)
          questions << question
        }
        
        q.generate_quiz_data

        q.save!
        q.publish!

        _course.quizzes << q
      end    

      }

      # Fetch module test data and create the appropriate modules
      course_data["modules"].each{ |mod|

        _course.create_module(mod)

      }




  }

  courses[0]

end

# Combine a list of task objects together into an aggregate, where all task instances are organized under their respective tasks.
def aggregate_task_objects(tasks)

  puts "Aggregating #{tasks.length} tasks into instances."
  result = []

  tasks.each { |task|
    task_entry = result.select {|item| item[:id] == task[:id]}[0]

    if task_entry.nil?
      task_entry = {}
      task_entry[:id] = task[:id]
      task_entry[:paremeterized_text] = task[:paremeterized_text]
      task_entry[:parameters] = task[:parameters]
      task_entry[:instances] = []
      
      result << task_entry

    end

    instance_data = {}
    instance_data[:id] = SecureRandom.uuid
    instance_data[:instance_text] = task[:instance_text]
    instance_data[:mapping] = task[:mapping]

    task_entry[:instances] << instance_data

  }

  result

end

def create_task_instances(test_course)

  tasks = []

  task = AgentTask.new({
    id: "9b30427c-2025-48db-baed-2cff271cd819",
    parameterized_text: "Task: In the course '[[Course]]' switch from your current group '[[Group 1]]' to the group '[[Group 2]]' within the 'Student Groups' group set."
  })

  task.populate(test_course) { |course, task|

      # find a group that the logged-in user is part of.
      group1 = course.groups.select {|group| (group.users.include? course.logged_in_user) && (!AgentTask.groups.include? group)}.first

      if group1.nil?
        puts "Cannot find group containing the logged in user for task #{task.id}"
        return
      end

      # find a group that the logged-in user in not a part of. 
      group2 = course.groups.select {|group| (!group.users.include? course.logged_in_user) && (!AgentTask.groups.include? group) }.first

      if group2.nil?
        puts "Cannot find group that does not contain the logged in user for task #{task.id}"
        return
      end

      # Register these groups as being used.
      AgentTask.groups << group1 
      AgentTask.groups << group2

      task.instance_variable_set(:@group1, group1)
      task.instance_variable_set(:@group2, group2)

      # Generate task instance text
      task.update_initalized_text("Course", course.course.name)
      task.update_initalized_text("Group 1", group1.name)
      task.update_initalized_text("Group 2", group2.name)

  }

  tasks << task

  task = AgentTask.new({
    id: "0b925826-6333-43cf-9eb0-4b5cb49a7e7d",
    parameterized_text: "Task: In the course '[[Course]]' use the Syllabus page to find the due date for the assignment titled '[[Assignment]]' and list the due date as displayed in the Course Summary section."
  })

  task.populate(test_course) { |course,task|

    assignment = course.assignments.select {|a| !AgentTask.assignments.include? a}.first

    if assignment.nil?
      puts "Cannot find assignment for task #{task.id}"
      return
    end

    # Register this assignment as being used.
    AgentTask.assignments << assignment

    task.instance_variable_set(:@assignment, assignment)

    # Generate task instance text
    task.update_initalized_text("Course", course.course.name )
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: "0be01f7a-0c6e-49c3-af20-52f9b97ef728",
    parameterized_text: "Task: View the feedback left by your instructor for the assignment '[[Assignment]]' in the course '[[Course]]', and add a comment saying 'Thank you for the feedback!' using the Feedback sidebar."
  })

  task.populate(test_course) { |course,task|

    assignment = course.assignments.select {|a| # Find an assignment
      # that has a submission by the logged in user.
      submission = a.submissions.find_by(user_id: course.logged_in_user.id)
      # where that submission has a comment provided by the course instructor. 
      comment_by_teacher = submission.submission_comments.select {|comment| comment.author == course.teacher}.first
      comment_by_teacher 
  }.first

    if (assignment.nil?) || (AgentTask.assignments.include? assignment)
      puts "Could not find assignment with submission and instructor feedback for task #{task.id}"
      return 
    end

    # Register this assignment as being used.
    AgentTask.assignments << assignment

    # Generate task instance text
    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: "117ad520-4107-4488-9101-a2a951daebdf", 
    parameterized_text: 'Task: View the rubric for the quiz titled "[[Quiz]]" in the course "[[Course]]" by navigating to the Grades page, clicking on "[[Quiz]]," and then clicking the "Show Rubric" link on the submission details page.'
  })

  task.populate(test_course) {|course, task| 

    # Look for an unused quiz with a rubric
    quiz = course.quizzes.select{ |q| (!AgentTask.quizzes.include? q ) && (!q.assignment.rubric_association.nil?)}.first 

    if quiz.nil?
      puts "Cannot find quiz for task #{task.id}"
      return
    end

    #Register this assignment as being used.
    AgentTask.quizzes << quiz
    task.instance_variable_set(:@quiz, quiz)

    # Generate task instance text
    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Quiz", quiz.title)
  

  }

  tasks << task

  task = AgentTask.new({
    id: '14875b88-4d4f-44be-a989-cff2a705958e' ,
    parameterized_text: 'Task: Create a new student group named "[[Group]]" in the course "[[Course]]", set the group membership to "Membership by invitation only", and invite students named "[[User 1]]" and "[[User 2]]" to join the group.'
  })

  task.populate(test_course) {|course,task| 


    group_name = course.unused_group_names.select {|name| !AgentTask.used_group_names.include? name}.first

    AgentTask.used_group_names << group_name

    user_1 = course.classmates.select {|classmate| (!AgentTask.users.include? classmate)}.first

    AgentTask.users << user_1

    user_2 = course.classmates.select {|classmate| (!AgentTask.users.include? classmate)}.first

    AgentTask.users << user_2

    task.instance_variable_set(:@group_name, group_name)
    task.instance_variable_set(:@user_1, user_1)
    task.instance_variable_set(:@user_2, user_2)

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Group", group_name)
    task.update_initalized_text("User 1", user_1.name)
    task.update_initalized_text("User 2", user_2.name)

  }

  tasks << task

  task = AgentTask.new({
    id: "0b62c5d4-a6fe-4083-9123-45e3087c1440",
    parameterized_text: 'Task: In your group "[[Group]]" for the course [[Course]], create a new announcement with the title "[[Announcement]]" and the following content: "[[Announcement Message]]" Allow other users to like the announcement, and publish it.'
  })

  task.populate(test_course) { |course, task|

    # pick a group which hasn't been used for a task before and to which the logged in user belongs.
    group = course.groups.select{|g| (!AgentTask.groups.include? g) && (g.users.include? course.logged_in_user)}.first 

    if group.nil?
      puts "Could not find group for task #{task.id}"
      return
    end

    announcement_data = course.unused_announcements.select{|a| !AgentTask.used_announcements.include? a}.first

    AgentTask.used_announcements << announcement_data

    task.instance_variable_set(:@announcement_title, announcement_data["title"])
    task.instance_variable_set(:@announcement_message, announcement_data["message"])
    task.instance_variable_set(:@group, group)

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Group", group.name)
    task.update_initalized_text("Announcement", announcement_data["title"])
    task.update_initalized_text("Announcement Message", announcement_data["message"])

  }

  tasks << task

  task = AgentTask.new({
    id: "14fe049e-9db4-497a-97c9-507a2c60d55e",
    parameterized_text: 'Task: Subscribe to the "[[Discussion]]" discussion in the "[[Course]]" course so that you receive notifications when new comments are posted.'
  })

  task.populate(test_course) {|course, task|

    discussion = course.discussions.select{|d| !AgentTask.discussions.include? d}.first
    
    if discussion.nil? 
      puts "Could not find discussion for task #{task.id}"
      return
    end
    
    AgentTask.discussions << discussion

    task.instance_variable_set(:@discussion, discussion)

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Discussion", discussion.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '158b7ece-5c61-466f-9447-9ab9e43c0b03',
    parameterized_text: 'Task: Take the "[[Quiz]]" in the "[[Course]]" course, answer all questions, flag question 3 for review, and submit the quiz when finished.'
  })
  
  task.populate(test_course) { |course, task|

    # Find a quiz with at least 3 questions
    quiz = course.quizzes.select{|q| (!AgentTask.quizzes.include? q) && q.quiz_questions.length >= 3}.first

    if quiz.nil? 
      puts "Cannot find quiz for task #{task.id}"
      return
    end

    AgentTask.quizzes << quiz

    task.instance_variable_set(:@quiz, quiz)

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Quiz", quiz.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '175397c6-1439-40ab-8b74-8f0e479ef8c5',
    parameterized_text: 'Task: In the course "[[Course]]," open the quiz titled "[[Quiz]]" and answer Question [[Question Index]], which is a short answer question, by typing "[[Answer]]" into the provided text box.'
  })

  task.populate(test_course) {|course, task|

    # Fetch quiz directly from test data to identify correct answer easily.
    test_data = YAML.load_file "/usr/src/app/spec/fixtures/data_generation/test_data.yaml"
    course_data = test_data["courses"].select{|c|c["name"] == course.course.name}.first

    # Create a list of used quiz names to ensure we're not re-using a quiz used by a different task.
    used_quiz_names = []
    AgentTask.quizzes.each {|q| used_quiz_names << q.title}

    quiz = course_data["quizzes"].select {|q| (!used_quiz_names.include? q["title"]) && (q["questions"].length >= 2) && (!q["questions"].select{|question| question["question_type"] == "short_answer_question"}.first.nil?)}.first

    if quiz.nil?
      puts "Could not find quiz for task #{task.id}"
      return
    end

    # Find a short answer question in the quiz
    question = quiz["questions"].select{|question| question["question_type"] == "short_answer_question"}.first
    question_index = quiz["questions"].find_index(question)
    answer = question["answers"].select{|a| a["weight"] == 100}.first

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Quiz", quiz["title"])
    task.update_initalized_text("Question Index", (question_index + 1).to_s)
    task.update_initalized_text("Answer", answer["text"])


    _quiz = course.quizzes.select{|q| q.title == quiz["title"]}.first
    AgentTask.quizzes << _quiz # register the quiz as being used. 

  }

  tasks << task

  task = AgentTask.new({
    id: '1977dbaa-1d14-4b08-a40b-0090df524371',
    parameterized_text: 'Task:  In your group ([[Group]]) for the course "[[Course]]" close your own discussion titled "[[Discussion]]" for comments.'
  })

  task.populate(test_course){|course,task|

    group = course.groups.select {|g| (!AgentTask.groups.include? g) && (g.users.include? course.logged_in_user) && (!g.discussion_topics.select {|dt| dt.user == course.logged_in_user}.first.nil?) }.first

    if group.nil?
      puts "Cannot find group for task #{task.id}"
      return 
    end

    AgentTask.groups << group

    discussion_topic = group.discussion_topics.select{|dt| dt.user == course.logged_in_user}.first
    
    if discussion_topic.nil?
      puts "Cannot find discussion topic for task #{task.id}"
      return
    end

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Group", group.name)
    task.update_initalized_text("Discussion", discussion_topic.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '19816faf-81ee-4235-8228-eb3d45e6bad3',
    parameterized_text: 'Task: View the details of the "[[Assignment]]" assignment in the "[[Course]]" course, including its due date, points possible, and any instructor instructions.

Steps to complete:

1. In the Course Navigation for "[[Course]]," click the Assignments link.
2. On the Assignments Index page, locate and click on the assignment titled "[[Assignment]]."
3. On the Assignment Summary page, review the assignment title, due date, points possible, and read any instructions provided by the instructor in the Details section.'
  })

  task.populate(test_course){ |course, task|

    assignment = course.assignments.select {|a| !AgentTask.assignments.include? a}.first

    if assignment.nil?
      puts "Could not find assignment for task #{task.id}"
      return
    end

    AgentTask.assignments << assignment

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '2b0a143f-fb9c-4f8e-9606-211e6bcb8171',
    parameterized_text: 'Task: In the course "[[Course]]," use the People page to search for the user named "[[User]]," view their profile details, and send them a message with the text: "Hi, I have a question about the lab assignment. Can we discuss it?"'
  })

  task.populate(test_course) {|course, task|

    user = course.classmates.select {|c| !AgentTask.users.include? c}.first

    if user.nil?
      puts "Could not find user for task #{task.id}"
      return 
    end

    AgentTask.users << user

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("User", user.name)

  }

  tasks << task

  task = AgentTask.new({
    id: '2f354ba2-b00c-4f3d-8b05-ae149f8e870d',
    parameterized_text: 'Task: In the course "[[Course]]" view the page titled "[[Page]]" by navigating to the Pages Index and selecting the page from the list.'
  })

  task.populate(test_course) {|course,task|

    page = course.pages.select{|p| !AgentTask.pages.include? p}.first

    if page.nil?
      puts "Could not find page for task #{task.id}"
      return
    end

    AgentTask.pages << page

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Page", page.title)
  }

  tasks << task

  task = AgentTask.new({
    id: '2fb04821-58a4-4b0e-90b9-2b24882f4582',
    parameterized_text: 'Task: In the course "[[Course]]," use the Quizzes page to find the quiz titled "[[Quiz]]," and view its availability dates, due date, point value, and number of questions. Write down the availability start date, due date, and the number of points the quiz is worth.'
  })

  task.populate(test_course) {|course, task|

    quiz = course.quizzes.select{|q| !AgentTask.quizzes.include? q}.first

    if quiz.nil?
      puts "Could not find quiz for task #{task.id}"
      return
    end

    AgentTask.quizzes << quiz

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Quiz", quiz.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '353feae6-0efa-4913-8220-8ab2567696b4',
    parameterized_text: 'Task: In the "[[Group]]" group, view the revision history of the page titled "[[Page]]" and identify the most recent edit and when it was made.'
  })

  task.populate(test_course) {|course, task|

    # Fetch group directly from test data to identify pages with update history easily.
    test_data = YAML.load_file "/usr/src/app/spec/fixtures/data_generation/test_data.yaml"
    course_data = test_data["courses"].select{|c|c["name"] == course.course.name}.first

    used_group_names = []
    AgentTask.groups.each {|group| used_group_names << group.name}

    group = course_data["groups"].select{|g| (!used_group_names.include? g["name"]) && (!g["pages"].nil?) && (!g["pages"].select{|p| !p["updates"].nil?}.first.nil?)}.first


    if group.nil?
      puts "Could not find a group for task #{task.id}"
      return
    end

    page = group["pages"].select{|p| !p["updates"].nil?}.first

    _group = course.groups.select {|grp| grp.name == group["name"]}.first
    AgentTask.groups << _group

    task.update_initalized_text("Group", group["name"])
    task.update_initalized_text("Page", page["title"])


  }

  tasks << task

  task = AgentTask.new({
    id: '37949dc8-cc9a-46ec-9a04-9fc70de7739a',
    parameterized_text: 'Task: In the course "[[Course]]," use the Assignments page to search for the assignment titled "[[Assignment]]." View the assignment details, including the due date, availability dates, point value, and any rubric provided.'
  })

  task.populate(test_course) {|course, task| 

    assignment = course.assignments.select { |a| !AgentTask.assignments.include? a}.first

    if assignment.nil?
      puts "Could not find assignment for task #{task.id}"
      return
    end

    AgentTask.assignments << assignment

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '382d57c2-b2e5-4024-9c05-9c5d195d2a27',
    parameterized_text: 'Task: In the course "[[Course]]," use the Course Home Page to remove the "[[Assignment]]" assignment from your To Do list in the sidebar.'
  })

  task.populate(test_course) {|course, task|

    assignment = course.assignments.select{|a| !AgentTask.assignments.include? a}.first

    if assignment.nil?
      puts "Cannot find assignment for task #{task.id}"
      return 
    end

    AgentTask.assignments << assignment

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '5718e37a-b1d1-4ec9-a223-7fd262419682',
    parameterized_text: 'Task: In your "[[Group]]" group, create a new discussion titled "[[Discussion]]," write "[[Discussion Message]]" allow group members to like the discussion, and add it to other group members\' to-do lists.'
  })

  task.populate(test_course) {|course,task|

    group = course.groups.select{|g| (!AgentTask.groups.include? g) && (g.users.include? course.logged_in_user)}.first

    if group.nil?
      puts "Could not find group for task #{task.id}"
      return
    end

    AgentTask.groups << group

    discussion_data = course.unused_discussions.select{|d| !AgentTask.used_discussions.include? d}.first
    AgentTask.used_discussions << discussion_data

    task.update_initalized_text("Group", group.name)
    task.update_initalized_text("Discussion", discussion_data["title"])
    task.update_initalized_text("Discussion Message", discussion_data["message"])
  }

  tasks << task

  task = AgentTask.new({
    id: 'a1c4e8bf-af9a-49c5-9672-5e83c0170b9b',
    parameterized_text: 'Task: Reply to the main discussion in the "[[Discussion]]" discussion in the "[[Course]]" course with the following text: "I believe that local communities can play a significant role in addressing climate change by implementing sustainable practices."'
  })

  task.populate(test_course) {|course, task|

    discussion = course.discussions.select{|d| !AgentTask.discussions.include? d}.first
    
    if discussion.nil?
      puts "Cannot find discussion for task #{task.id}"
      return
    end

    AgentTask.discussions << discussion

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Discussion", discussion.title)

  }

  tasks << task

  task = AgentTask.new({
    id: 'a5660a7c-dbac-48d4-ace3-fbd6bb71d57b',
    parameterized_text: 'Task: View the current groups you are enrolled in for the course "[[Course]]" by using the Global Navigation Menu in Canvas.'
  })

  task.populate(test_course) {|course, task|

    task.update_initalized_text("Course", course.course.name)

  }

  tasks << task

  task = AgentTask.new({
    id: 'a7ab7dbf-7c80-4a13-80a4-f09947504d51',
    parameterized_text: 'Task: Check if you can retake the "[[Quiz]]" in the "[[Course]]" course and note how many attempts you have remaining.

Steps:

1. In the "[[Course]]" course, click the Quizzes link in the course navigation.
2. Click the title "[[Quiz]]" to open the quiz.
3. On the quiz page, view the number of attempts you have taken and the number of attempts remaining.
4. Record the number of attempts you have remaining for the "[[Quiz]]."'
  })

  task.populate(test_course) {|course,task|

    quiz = course.quizzes.select{|q| !AgentTask.quizzes.include? q}.first

    if quiz.nil?
      puts "Cannot find quiz for task #{task.id}"
      return
    end

    AgentTask.quizzes << quiz

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Quiz", quiz.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '1c156f92-b926-4817-b78a-b8ad85de2484',
    parameterized_text: 'Task: View the comments left by your instructor ([[Teacher]]) on your "[[Assignment]]" assignment in the "[[Course]]" course, and mark the comments as read. 

Steps to complete:
1. In Global Navigation, click the "Courses" link, then select "[[Course]]."
2. In Course Navigation, click the "Grades" link.
3. Locate the "[[Assignment]]" assignment in the grades list.
4. Click the Comment icon next to the "[[Assignment]]" assignment to view your instructor\'s comments.
5. Read all comments so that the unread indicator disappears.',
  })

  task.populate(test_course) {|course,task|

    assignment = course.assignments.select{|a| 

    if false # set to true for debugging
      puts "Assignment: #{a.title}"
      puts "!AgentTask.assignments.include? a #{!AgentTask.assignments.include? a}"
      puts "!a.submissions.where(user_id: course.logged_in_user).first.body.nil? #{!a.submissions.where(user_id: course.logged_in_user).first.body.nil?}"
      puts "Assignment submissions [#{a.submissions.length}]:"
      a.submissions.each_with_index {|s, index| puts "#{index} [#{s.student.name}] [nil:#{s.body.nil?}]: #{s.body}" }

      
      submission = a.submissions.where(user_id: course.logged_in_user).first
      if submission.nil?
        return
      end
      puts "submission #{submission}"
      puts "submission.body #{submission.body}"
      submission.submission_comments.each {|c| puts "Comment: #{c.comment} author: #{c.author}"}
      puts "!a.submissions.where(user_id: course.logged_in_user).first.submission_comments.select{|c| c.author == course.teacher}.first.nil? #{!a.submissions.where(user_id: course.logged_in_user).first.submission_comments.select{|c| c.author == course.teacher}.first.nil?}"
    end

    (!AgentTask.assignments.include? a) && # Find an assignment that hasn't already been used.
       (!a.submissions.where(user_id: course.logged_in_user).first.body.nil?) && # Where the logged in user has made a submission whose body isn't nil
       (!a.submissions.where(user_id: course.logged_in_user).first.submission_comments.select{|c| c.author == course.teacher}.first.nil?) # And the teacher of the course has left a comment on their submission
      }.first

    if assignment.nil?
      puts "Could not find assignment for task #{task.id}"
      return
    end

    AgentTask.assignments << assignment

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Teacher", course.teacher.name)
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '1bfdc4bc-1ab2-4846-b840-4c65d9f9c83f',
    parameterized_text: 'Task: In the Canvas course "[[Course]]," locate and view the peer feedback you received for the assignment titled "[[Assignment]]" by accessing the submission details page and clicking the "View Feedback" button.'
  })

  task.populate(test_course) {|course, task| 

    assignment = course.assignments.select{|a| 
      (!AgentTask.assignments.include? a) && # Find an assignment that hasn't already been used.
       (!a.submissions.where(user_id: course.logged_in_user).first.body.nil?) && # Where the logged in user has made a submission whose body isn't nil
       (!a.submissions.where(user_id: course.logged_in_user).first.submission_comments.select{|c| course.classmates.include? c.author}.first.nil?) # And the teacher of the course has left a comment on their submission
    }.first

    if assignment.nil?
      puts "Cannot find assignment for task #{task.id}"
      return
    end

    AgentTask.assignments << assignment

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '229bb30d-7652-40a9-934d-3e14d54e7ab9',
    parameterized_text: 'Task: In the course "[[Course]]," open the discussion titled "[[Discussion]]," and manually mark the reply from "[[User]]" as unread.'
  })

  task.populate(test_course) {|course, task|

    discussion = course.discussions.select{|d| 

    if false # set to true for debugging
      puts "Discussion: #{d.title}"
      puts "!AgentTask.discussions.include? d #{!AgentTask.discussions.include? d}"
      puts "!d.discussion_entries.select{|e| course.classmates.include? e.user}.first.nil? #{!d.discussion_entries.select{|e| course.classmates.include? e.user}.first.nil?}"
      puts "Entries: #{d.discussion_entries.length}"
      
      d.discussion_entries.each_with_index {|entry, index| 
        puts "[#{index} - #{entry.user.name}] #{entry.message}"
      }

    end
    
    (!AgentTask.discussions.include? d) && (!d.discussion_entries.select{|e| course.classmates.include? e.user}.first.nil?) }.first

    if discussion.nil?
      puts "Cannot find discussion for task #{task.id}"
      return
    end

    AgentTask.discussions << discussion

    reply = discussion.discussion_entries.select{|e| course.classmates.include? e.user}.first
    classmate = reply.user

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Discussion", discussion.title)
    task.update_initalized_text("User", classmate.name)


  }

  tasks << task

  task = AgentTask.new({
    id: '2776ed0f-e34e-4ffc-8884-9720a48a7420',
    parameterized_text: 'Task: In the course "[[Course]]," reply to the announcement titled "[[Announcement]]" by posting the message "Great announcement, @[[User]]! Looking forward to this week." and mention the user [[User]] in your reply.'
  })

  task.populate(test_course) {|course, task| 

    announcement = course.announcements.select {|a| (!AgentTask.announcements.include? a) }.first

    if announcement.nil?
      puts "Cannot find announcement for task #{task.id}"
      return 
    end

    AgentTask.announcements << announcement


    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Announcement", announcement.title)
    task.update_initalized_text("User", announcement.user.name)
  }

  tasks << task

  task = AgentTask.new({
    id:'279dcf3e-77f5-4a1b-8ced-ebdb8bb7e462',
    parameterized_text: 'Task: Submit a peer review comment for the discussion "[[Discussion]]" in the course "[[Course]]" by reviewing the assigned student reply and entering the following comment in the comment sidebar: "Great analysis! I especially liked your use of recent data to support your points." Then, click the Save button to complete the peer review.'
  })

  task.populate(test_course){ |course,task|

    discussion = course.discussions.select{|d| (!AgentTask.discussions.include? d) && (!d.assignment.nil?)}.first 

    if discussion.nil?
      puts "Cannot find discussion for task #{task.id}"
      return
    end

    AgentTask.discussions << discussion

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Discussion", discussion.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '29d80dd0-2506-41bc-ad55-40db3359b84c',
    parameterized_text: 'Task: Take the quiz titled "[[Quiz]]" in the course "[[Course]]," answering each question as it appears on the screen, and use the Next button to advance to the next question after answering. Do not leave any question blank.'
  })

  task.populate(test_course){|course,task|

    quiz = course.quizzes.select{|q|
    
    if false # Set to true for debugging
      puts "Quiz: #{q.title} - one_question_at_a_time? #{q.one_question_at_a_time}"
    end
    
    (!AgentTask.quizzes.include? q) && q.one_question_at_a_time}.first

    if quiz.nil?
      puts "Cannot find quiz for task #{task.id}"
      return
    end

    AgentTask.quizzes << quiz

    task.update_initalized_text('Course', course.course.name)
    task.update_initalized_text('Quiz', quiz.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '3b389112-ccb7-4272-853e-8dbe81a1c6c8',
    parameterized_text: 'Task: Delete the page titled "[[Page]]" from the "[[Group]]" on your [[Course]] course in Canvas.

Steps to complete:

1. In Global Navigation, click the "Groups" link.
2. Select "[[Group]]" from your list of groups.
3. In the group navigation, click the "Pages" link.
4. Click the "View All Pages" button.
5. In the Pages Index, select the checkbox next to the page titled "[[Page]]".
6. Click the "Delete" button.
7. In the confirmation dialog, click the "Delete" button to confirm deletion of the "[[Page]]" page.'
  })

  task.populate(test_course) {|course, task|

    group = course.groups.select{|g| 
    
    if false # set to true for debugging
      puts "Group: #{g.name}"
      puts "!AgentTask.groups.include? g #{!AgentTask.groups.include? g}"
      puts "g.users.include? course.logged_in_user #{g.users.include? course.logged_in_user}"
      puts "g.wiki_pages.length >= 1 #{g.wiki_pages.length >= 1}"
    end

    (!AgentTask.groups.include? g) && (g.users.include? course.logged_in_user) && (g.wiki_pages.length >= 1)}.first

    if group.nil?
      puts "Cannot find group for task #{task.id}"
      return
    end

    AgentTask.groups << group

    page = group.wiki_pages.first

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Group", group.name)
    task.update_initalized_text("Page", page.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '45974a3d-36dc-409e-9fe4-8cbd0adc3517',
    parameterized_text: 'Task: Delete the announcement titled "[[Announcement]]" from the "[[Group]]" group in the [[Course]] course on Canvas.'
  })

  task.populate(test_course) {|course, task|

    group = course.groups.select{|g| (!AgentTask.groups.include? g) && (!g.announcements.select{|a| a.user == course.logged_in_user}.first.nil?)}.first

    if group.nil?
      puts "Could not find group for task #{task.id}"
      return
    end

    AgentTask.groups << group
    
    announcement = group.announcements.select{|a| a.user == course.logged_in_user}.first

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Group", group.name)
    task.update_initalized_text("Announcement", announcement.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '4bbdbb35-c934-40ab-a042-034f04e2de77',
    parameterized_text: 'Task: View the peer feedback you received on the "[[Assignment]]" assignment in the "[[Course]]" course using the Assignment Details page.'
  })

  task.populate(test_course) {|course, task| 

    assignment = course.assignments.select{|a| 
      (!AgentTask.assignments.include? a) && # Find an assignment that hasn't already been used.
       (!a.submissions.where(user_id: course.logged_in_user).first.body.nil?) && # Where the logged in user has made a submission whose body isn't nil
       (!a.submissions.where(user_id: course.logged_in_user).first.submission_comments.select{|c| course.classmates.include? c.author}.first.nil?) # And the teacher of the course has left a comment on their submission
    }.first

    if assignment.nil?
      puts "Cannot find assignment for task #{task.id}"
      return
    end

    AgentTask.assignments << assignment

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Assignment", assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: '6242d2f1-f67e-4d56-a856-b9a5f536672f',
    parameterized_text: 'Task: In the course "[[Course]]," create a new course discussion titled "[[Discussion]]." In the discussion content, enter the following text: "[[Discussion Message]]" Save the discussion.'
  })

  task.populate(test_course) {|course, task|
    
    discussion_data = course.unused_discussions.select{|d| !AgentTask.used_discussions.include? d}.first

    AgentTask.used_discussions << discussion_data

    task.update_initalized_text("Course", course.course.name)
    task.update_initalized_text("Discussion", discussion_data["title"])
    task.update_initalized_text("Discussion Message", discussion_data["message"])
  }

  tasks << task

  puts "last task"
  puts task.to_hash

  puts "#{tasks.length} tasks defined!"

  task_objects = []
  
  tasks.each {|t| 
    #puts "Task: #{t.id}\n#{t.instance_text}"
    task_objects << t.to_hash
  }

  task_instances = aggregate_task_objects(task_objects)
  puts "generated #{task_instances.length} task instances"

  # output the instances to yaml/json format.
  File.open('tasks.json', 'w') {|json_file| json_file.write task_instances.to_json}
  File.open('tasks.yaml', "w") {|yaml_file| yaml_file.write task_instances.to_yaml}

end



=begin
Run with:
docker-compose run --remove-orphans web bundle exec rails runner spec/fixtures/data_generation/custom_data.rb
=end

#explore
test_course = generate_test_environment
create_task_instances(test_course)
#puts Account.default.settings.pretty_inspect