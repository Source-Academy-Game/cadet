defmodule CadetWeb.UserControllerTest do
  use CadetWeb.ConnCase

  import Cadet.Factory

  alias Cadet.Repo
  alias CadetWeb.UserController
  alias Cadet.Assessments.{Assessment, AssessmentType, Submission}
  alias Cadet.Accounts.GameStates

  test "swagger" do
    assert is_map(UserController.swagger_definitions())
    assert is_map(UserController.swagger_path_index(nil))
  end

  describe "GET /user" do
    @tag authenticate: :student
    test "success, student non-story fields", %{conn: conn} do
      user = conn.assigns.current_user
      assessment = insert(:assessment, %{is_published: true})
      question = insert(:question, %{assessment: assessment})

      submission =
        insert(:submission, %{
          assessment: assessment,
          student: user,
          status: :submitted,
          xp_bonus: 100
        })

      insert(:answer, %{
        question: question,
        submission: submission,
        grade: 50,
        adjustment: -10,
        xp: 20,
        xp_adjustment: -10
      })

      not_submitted_assessment = insert(:assessment, is_published: true)
      not_submitted_question = insert(:question, assessment: not_submitted_assessment)

      not_submitted_submission =
        insert(:submission, assessment: not_submitted_assessment, student: user)

      insert(
        :answer,
        question: not_submitted_question,
        submission: not_submitted_submission,
        grade: 0,
        adjustment: 0
      )

      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
        |> Map.delete("story")

      expected = %{
        "name" => user.name,
        "role" => "#{user.role}",
        "xp" => 110,
        "grade" => 40,
        "maxGrade" => question.max_grade,
        "gameStates" => %{"collectibles" => %{}, "completed_quests" => []}
      }

      assert expected == resp
    end

    # This also tests for the case where assessment has no submission
    @tag authenticate: :student
    test "success, student story ordering", %{conn: conn} do
      early_assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -3))
      late_assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -1))

      for assessment <- early_assessments ++ late_assessments do
        resp_story =
          conn
          |> get("/v1/user")
          |> json_response(200)
          |> Map.get("story")

        expected_story = %{
          "story" => assessment.story,
          "playStory" => true
        }

        assert resp_story == expected_story

        {:ok, _} = Repo.delete(assessment)
      end
    end

    @tag authenticate: :student
    test "success, student story skips assessment without story", %{conn: conn} do
      assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -1))

      assessments
      |> List.first()
      |> Assessment.changeset(%{story: nil})
      |> Repo.update()

      resp_story =
        conn
        |> get("/v1/user")
        |> json_response(200)
        |> Map.get("story")

      expected_story = %{
        "story" => Enum.fetch!(assessments, 1).story,
        "playStory" => true
      }

      assert resp_story == expected_story
    end

    @tag authenticate: :student
    test "success, student story skips unopen assessments", %{conn: conn} do
      build_assessments_starting_at(Timex.shift(Timex.now(), days: 1))
      build_assessments_starting_at(Timex.shift(Timex.now(), months: -1))

      valid_assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -1))

      for assessment <- valid_assessments do
        assessment
        |> Assessment.changeset(%{is_published: false})
        |> Repo.update!()
      end

      resp_story =
        conn
        |> get("/v1/user")
        |> json_response(200)
        |> Map.get("story")

      expected_story = %{
        "story" => nil,
        "playStory" => false
      }

      assert resp_story == expected_story
    end

    @tag authenticate: :student
    test "success, student story skips attempting/attempted/submitted", %{conn: conn} do
      user = conn.assigns.current_user

      early_assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -3))
      late_assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -1))

      # Submit for i-th assessment, expect (i+1)th story to be returned
      for status <- [:attempting, :attempted, :submitted] do
        for [tester, checker] <-
              Enum.chunk_every(early_assessments ++ late_assessments, 2, 1, :discard) do
          insert(:submission, %{student: user, assessment: tester, status: status})

          resp_story =
            conn
            |> get("/v1/user")
            |> json_response(200)
            |> Map.get("story")

          expected_story = %{
            "story" => checker.story,
            "playStory" => true
          }

          assert resp_story == expected_story
        end

        Repo.delete_all(Submission)
      end
    end

    @tag authenticate: :student
    test "success, return most recent assessment when all are attempted", %{conn: conn} do
      user = conn.assigns.current_user

      early_assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -3))
      late_assessments = build_assessments_starting_at(Timex.shift(Timex.now(), days: -1))

      for assessment <- early_assessments ++ late_assessments do
        insert(:submission, %{student: user, assessment: assessment, status: :attempted})
      end

      resp_story =
        conn
        |> get("/v1/user")
        |> json_response(200)
        |> Map.get("story")

      expected_story = %{
        "story" => late_assessments |> List.first() |> Map.get(:story),
        "playStory" => false
      }

      assert resp_story == expected_story
    end

    @tag authenticate: :staff
    test "success, staff", %{conn: conn} do
      user = conn.assigns.current_user

      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
        |> Map.delete("story")

      expected = %{
        "name" => user.name,
        "role" => "#{user.role}",
        "grade" => 0,
        "maxGrade" => 0,
        "xp" => 0,
        "gameStates" => %{"collectibles" => %{}, "completed_quests" => []}
      }

      assert expected == resp
    end

    test "unauthorized", %{conn: conn} do
      conn = get(conn, "/v1/user", nil)
      assert response(conn, 401) =~ "Unauthorised"
    end

    defp build_assessments_starting_at(time) do
      type_order_map =
        AssessmentType.__enum_map__()
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {type, idx}, acc -> Map.put(acc, type, idx) end)

      AssessmentType.__enum_map__()
      |> Enum.map(
        &build(:assessment, %{
          type: &1,
          is_published: true,
          open_at: time,
          close_at: Timex.shift(time, days: 10)
        })
      )
      |> Enum.shuffle()
      |> Enum.map(&insert(&1))
      |> Enum.sort(&(type_order_map[&1.type] < type_order_map[&2.type]))
    end
  end

  describe "PUT /user" do
    @tag authenticate: :student
    test "success, student adding collectibles", %{conn: conn} do
      user = conn.assigns.current_user
      new_game_states = %{
        "completed_quests" => ["haha"],
        "collectibles" => %{
          "HAHA" => "HAHA.png"
        }
      }
      GameStates.update(user, new_game_states)
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
      assert new_game_states == resp["gameStates"]
    end

    @tag authenticate: :student
    test "success, student deleting collectibles", %{conn: conn} do
      user = conn.assigns.current_user
      new_game_states = %{
        "completed_quests" => ["haha"],
        "collectibles" => %{
          "HAHA" => "HAHA.png"
        }
      }
      GameStates.update(user, new_game_states)
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
      assert new_game_states == resp["gameStates"]

      GameStates.clear(user)
      resp_2 =
        conn
        |> get("/v1/user")
        |> json_response(200)
        assert %{
          "completed_quests" => [],
          "collectibles" => %{}
        } == resp_2["gameStates"]
    end

    @tag authenticate: :student
    test "success, student retrieving collectibles", %{conn: conn} do
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
      assert %{
        "completed_quests" => [],
        "collectibles" => %{}
      } == resp["gameStates"]
    end


    @tag authenticate: :staff
    test "forbidden, staff adding collectibles", %{conn: conn} do
      user = conn.assigns.current_user
      new_game_states = %{
        "completed_quests" => ["haha"],
        "collectibles" => %{
          "HAHA" => "HAHA.png"
        }
      }

      assert GameStates.update(user, new_game_states) == {:error, {:forbidden, "Please try again later."}}
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
      assert %{
        "completed_quests" => [],
        "collectibles" => %{}
      } == resp["gameStates"]
    end

    @tag authenticate: :staff
    test "forbidden, staff deleting collectibles", %{conn: conn} do
      user = conn.assigns.current_user
      new_game_states = %{
        "completed_quests" => ["haha"],
        "collectibles" => %{
          "HAHA" => "HAHA.png"
        }
      }
      assert GameStates.update(user, new_game_states) == {:error, {:forbidden, "Please try again later."}}
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
        assert %{
          "completed_quests" => [],
          "collectibles" => %{}
        } == resp["gameStates"]

        assert GameStates.clear(user) == {:error, {:forbidden, "Please try again later."}}
      resp_2 =
        conn
        |> get("/v1/user")
        |> json_response(200)
        assert %{
          "completed_quests" => [],
          "collectibles" => %{}
        } == resp_2["gameStates"]
    end

    @tag authenticate: :staff
    test "success, staff retrieving collectibles", %{conn: conn} do
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
      assert %{
        "completed_quests" => [],
        "collectibles" => %{}
      } == resp["gameStates"]
    end

    @tag authenticate: :admin
    test "forbidden, admin adding collectibles", %{conn: conn} do
      user = conn.assigns.current_user
      new_game_states = %{
        "completed_quests" => ["haha"],
        "collectibles" => %{
          "HAHA" => "HAHA.png"
        }
      }

      assert GameStates.update(user, new_game_states) == {:error, {:forbidden, "Please try again later."}}
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
      assert %{
        "completed_quests" => [],
        "collectibles" => %{}
      } == resp["gameStates"]
    end

    @tag authenticate: :admin
    test "forbidden, admin deleting collectibles", %{conn: conn} do
      user = conn.assigns.current_user
      new_game_states = %{
        "completed_quests" => ["haha"],
        "collectibles" => %{
          "HAHA" => "HAHA.png"
        }
      }
      assert GameStates.update(user, new_game_states) == {:error, {:forbidden, "Please try again later."}}
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
        assert %{
          "completed_quests" => [],
          "collectibles" => %{}
        } == resp["gameStates"]

        assert GameStates.clear(user) == {:error, {:forbidden, "Please try again later."}}
      resp_2 =
        conn
        |> get("/v1/user")
        |> json_response(200)
        assert %{
          "completed_quests" => [],
          "collectibles" => %{}
        } == resp_2["gameStates"]
    end

    @tag authenticate: :admin
    test "success, admin retrieving collectibles", %{conn: conn} do
      resp =
        conn
        |> get("/v1/user")
        |> json_response(200)
      assert %{
        "completed_quests" => [],
        "collectibles" => %{}
      } == resp["gameStates"]
    end
  end
end
